// Bridges Godot's Web export to a real browser file picker, since Godot's
// own FileDialog can't provide it on Web: DisplayServer never reports
// FEATURE_NATIVE_DIALOG_FILE for the Web platform in any browser, so
// use_native_dialog silently does nothing there and it always falls back to
// Godot's own in-engine dialog browsing an empty virtual filesystem.
//
// A plain <input type="file"> is the one file-picking mechanism that's
// actually native and universal (Chromium, Firefox and its forks e.g. Zen
// Browser, Safari all support it) -- used by scripts/autoload/WebFilePicker.gd.
// Deliberately no <input accept> filter: browsers grey out files that don't
// match it, and a real target file appearing unselectable for any reason
// (an unexpected extension, a cloud-sync placeholder, a filter-string quirk)
// was a recurring source of confusion. Godot validates the picked filename
// itself after the fact instead.
//
// The result comes back via a plain global object polled from GDScript
// (see WebFilePicker.gd's docstring for why: JavaScriptBridge.create_callback
// callbacks have repeatedly failed to fire with no error on either side in
// this project, while JavaScriptBridge.eval() has been reliable both ways).

function _wmBufferToBase64(buffer) {
	let binary = "";
	const bytes = new Uint8Array(buffer);
	const chunkSize = 0x8000;
	for (let i = 0; i < bytes.length; i += chunkSize) {
		binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunkSize));
	}
	return btoa(binary);
}

// wmFileResult starts null; once a pick finishes (success, failure, or
// cancel) it becomes {success, name, payload} for GDScript to poll for and
// consume. payload is the file's text for a .json file, base64-encoded
// bytes otherwise; on failure name carries the reason ("canceled" on cancel).
window.wmFileResult = null;

function wmPickFile() {
	const input = document.createElement("input");
	input.type = "file";
	// display:none keeps some browsers (notably Firefox) from firing a
	// native picker on .click() at all -- position off-screen instead so
	// the element stays part of the render tree without being visible.
	input.style.position = "fixed";
	input.style.top = "-1000px";
	input.style.left = "-1000px";
	input.style.opacity = "0";
	document.body.appendChild(input);

	function finish(success, name, payload) {
		window.wmFileResult = { success: success, name: name, payload: payload };
		if (input.parentNode) input.parentNode.removeChild(input);
	}

	input.addEventListener("cancel", () => finish(false, "canceled", ""), { once: true });

	input.addEventListener("change", () => {
		const file = input.files && input.files[0];
		if (!file) {
			finish(false, "No file selected", "");
			return;
		}
		if (file.name.toLowerCase().endsWith(".json")) {
			file.text()
				.then((text) => finish(true, file.name, text))
				.catch((e) => finish(false, String(e), ""));
		} else {
			file.arrayBuffer()
				.then((buffer) => finish(true, file.name, _wmBufferToBase64(buffer)))
				.catch((e) => finish(false, String(e), ""));
		}
	}, { once: true });

	input.click();
}

window.wmPickFile = wmPickFile;
