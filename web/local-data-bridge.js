// Bridges Godot's Web export to the browser's File System Access API, so
// the game can read/write a single folder on the player's own disk (skins
// + world.json) instead of uploading anything or relying on the browser's
// downloads folder. See scripts/autoload/LocalDataFolder.gd for the
// GDScript side of this bridge.
//
// Only Chromium-based browsers (Chrome, Edge, Opera) implement this API as
// of this writing -- wm_fs_supported() lets the game detect that and fall
// back to the ordinary file-dialog/download flow elsewhere.
//
// Every function here takes a Godot-created callback (via
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
