// Bridges Godot's Web export to real browser file access, since Godot's own
// FileDialog can't provide it on Web: DisplayServer never reports
// FEATURE_NATIVE_DIALOG_FILE for the Web platform in any browser, so
// use_native_dialog silently does nothing there and it always falls back
// to Godot's own in-engine dialog browsing an empty virtual filesystem.
//
// Two independent mechanisms, used by two different GDScript autoloads:
// - wm_fs_* (scripts/autoload/LocalDataFolder.gd): the File System Access
//   API, which lets the player grant access to one real folder on their
//   disk once and read/write files in it silently afterward. Only
//   Chromium-based browsers (Chrome, Edge, Opera) implement it --
//   wm_fs_supported() lets the game detect that.
// - wm_pick_file (scripts/autoload/WebFilePicker.gd): a plain
//   <input type="file">, which is universally supported (including
//   Firefox and its forks, e.g. Zen Browser, and Safari) but only ever
//   picks one file at a time with no memory of "the folder" -- the
//   fallback for browsers wm_fs_supported() says no to.
//
// Every wm_fs_* function here takes a Godot-created callback (via
// JavaScriptBridge.create_callback) as its last argument and calls it with
// (success: bool, payload: string) -- payload is either the result (a
// folder/file name, base64 image bytes, or file text) or an error message.

function wm_fs_supported() {
	return typeof window.showDirectoryPicker === "function";
}

let _wmDirHandle = null;

async function wm_fs_choose_folder(onDone) {
	try {
		_wmDirHandle = await window.showDirectoryPicker({ mode: "readwrite" });
		onDone(true, _wmDirHandle.name);
	} catch (e) {
		onDone(false, String(e));
	}
}

async function wm_fs_list_images(onDone) {
	if (!_wmDirHandle) {
		onDone(false, "No folder chosen");
		return;
	}
	try {
		const names = [];
		for await (const entry of _wmDirHandle.values()) {
			if (entry.kind !== "file") continue;
			const lower = entry.name.toLowerCase();
			if (lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg")) {
				names.push(entry.name);
			}
		}
		onDone(true, JSON.stringify(names));
	} catch (e) {
		onDone(false, String(e));
	}
}

function _wmBufferToBase64(buffer) {
	let binary = "";
	const bytes = new Uint8Array(buffer);
	const chunkSize = 0x8000;
	for (let i = 0; i < bytes.length; i += chunkSize) {
		binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize));
	}
	return btoa(binary);
}

async function wm_fs_read_image(filename, onDone) {
	if (!_wmDirHandle) {
		onDone(false, "No folder chosen");
		return;
	}
	try {
		const fileHandle = await _wmDirHandle.getFileHandle(filename);
		const file = await fileHandle.getFile();
		const buffer = await file.arrayBuffer();
		onDone(true, _wmBufferToBase64(buffer));
	} catch (e) {
		onDone(false, String(e));
	}
}

async function wm_fs_write_text(filename, text, onDone) {
	if (!_wmDirHandle) {
		onDone(false, "No folder chosen");
		return;
	}
	try {
		const fileHandle = await _wmDirHandle.getFileHandle(filename, { create: true });
		const writable = await fileHandle.createWritable();
		await writable.write(text);
		await writable.close();
		onDone(true, "");
	} catch (e) {
		onDone(false, String(e));
	}
}

async function wm_fs_read_text(filename, onDone) {
	if (!_wmDirHandle) {
		onDone(false, "No folder chosen");
		return;
	}
	try {
		const fileHandle = await _wmDirHandle.getFileHandle(filename);
		const file = await fileHandle.getFile();
		onDone(true, await file.text());
	} catch (e) {
		onDone(false, String(e));
	}
}

// Universal fallback for browsers without the File System Access API
// (Firefox and its forks, e.g. Zen Browser; Safari): Godot's own FileDialog
// can't help here either, since DisplayServer never reports
// FEATURE_NATIVE_DIALOG_FILE for the Web platform in any browser -- it
// always falls back to Godot's own in-engine dialog browsing an empty
// virtual filesystem, not anything real. A plain <input type="file"> is
// the one file-picking mechanism that's actually native and universal.
//
// onDone(success, filenameOrReason, payload) -- payload is the file's text
// for a .json file, base64-encoded bytes otherwise. Canceling the picker
// calls onDone(false, "canceled", "").
function wm_pick_file(accept, onDone) {
	const input = document.createElement("input");
	input.type = "file";
	input.accept = accept;
	// display:none keeps some browsers (notably Firefox) from firing a
	// native picker on .click() at all -- position off-screen instead so
	// the element stays part of the render tree without being visible.
	input.style.position = "fixed";
	input.style.top = "-1000px";
	input.style.left = "-1000px";
	input.style.opacity = "0";
	document.body.appendChild(input);

	function cleanup() {
		if (input.parentNode) input.parentNode.removeChild(input);
	}

	input.addEventListener("cancel", () => {
		cleanup();
		onDone(false, "canceled", "");
	}, { once: true });

	input.addEventListener("change", () => {
		const file = input.files && input.files[0];
		cleanup();
		if (!file) {
			onDone(false, "No file selected", "");
			return;
		}
		if (file.name.toLowerCase().endsWith(".json")) {
			file.text()
				.then((text) => onDone(true, file.name, text))
				.catch((e) => onDone(false, String(e), ""));
		} else {
			file.arrayBuffer()
				.then((buffer) => onDone(true, file.name, _wmBufferToBase64(buffer)))
				.catch((e) => onDone(false, String(e), ""));
		}
	}, { once: true });

	input.click();
}
