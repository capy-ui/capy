let obj = null;
let networkRequests = [];
let networkRequestsCompletion = [];
let networkRequestsReadIdx = [];
let resources = [];

function readString(addr, len) {
	addr = addr >>> 0; // convert from i32 to u32
	len = len >>> 0;

	let utf8Decoder = new TextDecoder();
	let view = new Uint8Array(obj.instance.exports.memory.buffer);
	// console.debug("read string @ " + addr + " for " + len + " bytes");
	
	return utf8Decoder.decode(view.slice(addr, addr + len));
}

function writeString(addr, string) {
	let utf8Encoder = new TextEncoder();
	const bytes = utf8Encoder.encode(string);
	writeBytes(addr, bytes);
}

function writeBytes(addr, bytes) {
	addr = addr >>> 0; // convert from i32 to u32
		
	let view = new Uint8Array(obj.instance.exports.memory.buffer);
	view.set(bytes, addr);
}

function readBuffer(addr, len) {
	addr = addr >>> 0; // convert from i32 to u32
	len = len >>> 0;

	let view = new Uint8Array(obj.instance.exports.memory.buffer);
	return view.slice(addr, addr + len);
}

// 4 bytes for marking and 65536 bytes for data
let pendingAnswer = new SharedArrayBuffer(65540);
/**
	@param {string} type The type of the answer, can be "int", "float", "bool" or "bytes"
**/
function waitForAnswer(type) {
	const WAITING = 0;
	const DONE = 1;
	if (type == "bool") {
		return waitForAnswer("int") != 0;
	}
	
	const view = new Int32Array(pendingAnswer);
	view[0] = WAITING;
	// while (view.getUint8(0) != DONE) {
	// 	wait(10);
	// }
	Atomics.wait(view, 0, WAITING);

	switch (type) {
		case "int":
			const int = view[1] << 32 | view[2];
			return int;
		case "float":
			const float = new DataView(view.buffer).getFloat64(4);
			return float;
		case "bytes":
			const length = view[1];
			const bytes = new Uint8Array(pendingAnswer).slice(0x8, 0x8 + length);
			return bytes;
	}

	throw Error("Type invalid (" + type + ")");
}

/**
	Shared array buffer used for sleeping with Atomics.wait()
**/
const AB = new Int32Array(new SharedArrayBuffer(4));
/**
	@param {int} msecs Time to wait in milliseconds
**/
function wait(msecs) {
	const start = Date.now();
	while (Date.now() <= start + msecs) {
		Atomics.wait(AB, 0, 0, msecs - (Date.now() - start));
	}
}

const Errno = {
	SUCCESS: 0,
	BADF: 8,
	INVAL: 28
};

const ClockIds = {
	0: "REALTIME",
	1: "MONOTONIC",
	2: "PROCESS_CPUTIME_ID",
	3: "THREAD_CPUTIME_ID"
};

class WasiImplementation {
	constructor() {
		this.environ = {};
		this.logging = false;
	}

	/** Internal function. **/
	getMemory() {
		let view = new DataView(obj.instance.exports.memory.buffer);
		return view;
	}

	environAsString() {
		return Object.entries(this.environ)
			.map(x => x[0] + "=" + x[1])
			.join("\x00")
			+ "\x00"; // add a last NUL character to terminate the last string
	}

	/**
		@param {int} environ_count_ptr Pointer to a usize which will contain the number of environment variables
		@param {int} environ_buf_size_ptr Pointer to a usize which will contain the size of the environ buffer
	**/
	environ_sizes_get = (environ_count_ptr, environ_buf_size_ptr) => {
		if (this.logging)
			console.debug("environ_sizes_get(" + environ_count_ptr + ", " + environ_buf_size_ptr + ")");
		const view = this.getMemory();
		view.setUint32(environ_count_ptr, Object.entries(this.environ).length, true);
		view.setUint32(environ_buf_size_ptr, this.environAsString().length, true);
		return Errno.SUCCESS;
	}

	environ_get = (environ_ptr, environ_buf_ptr) => {
		if (this.logging)
			console.debug("environ_get(" + environ_ptr + ", " + environ_buf_ptr + ")");
		const view = this.getMemory();

		// The offset in the buffer at which the environment variable will be written
		let offset_in_buf = 0;
		// The index of the environment variable being currently written
		let environment_index = 0;
		for (const key in Object.keys(this.environ)) {
			view.setUint32(environ_ptr + environment_index * 4, environ_buf_ptr + offset_in_buf, true);

			const environment_variable = key + "=" + this.environ[key] + "\x00";
			writeString(environ_buf_ptr + offset_in_buf, environment_variable);

			offset_in_buf += environment_variable.length;
			environment_index++;
		}
		return Errno.SUCCESS;
	}

	clock_time_get = (clock_id, precision, timestamp_ptr) => {
		const clock = ClockIds[clock_id];
		if (this.logging)
			console.debug("clock_time_get(" + clock + ", " + precision + ", " + timestamp_ptr + ")");

		const view = this.getMemory();
		if (clock == "REALTIME") {
			console.assert(Number.isInteger(Date.now()));

			// The timestamp is multiplied after being converted to BigInt in order to avoid
			// floating point precision issues.
			const timestamp = BigInt(Date.now()) * 1_000_000n;
			view.setBigUint64(timestamp_ptr, timestamp, true);
			return Errno.SUCCESS;
		} else if (clock == "MONOTONIC" && performance) {
			const timestamp = BigInt(Math.floor(performance.now() * 1_000_000));
			view.setBigUint64(timestamp_ptr, timestamp, true);
			return Errno.SUCCESS;
		} else {
			// Unsupported clock.
			return Errno.INVAL;
		}
	}

	fd_write = (fd, iovs_ptr, iovs_len, nwritten_ptr) => {
		if (this.logging)
			console.debug("fd_write(" + fd + ", " + iovs_ptr + ", " + iovs_len + ", " + nwritten_ptr + ")");

		if (fd == 1 || fd == 2) { // standard output / standard error
			const view = this.getMemory();
			let written_bytes = 0;
			
			for (let i = 0; i < iovs_len; i++) {
				const iovec_addr = iovs_ptr + i * 8;
				const base = view.getUint32(iovec_addr, true);
				const len = view.getUint32(iovec_addr + 4, true);
				const string = readString(base, len);
				written_bytes += len;
				console.log(string);
			}
			view.setUint32(nwritten_ptr, written_bytes, true);
			return Errno.SUCCESS;
		} else {
			return Errno.BADF;
		}
	}

	path_open = (dirfd, dirflags, path_ptr, path_len, oflags, fs_rights_base, fs_rights_inheriting, fs_flags, fd) => {
		if (this.logging)
			console.debug("path_open(...)");
		return Errno.INVAL;
	}

	fd_read = (fd, iovs_ptr, iovs_len, nread_ptr) => {
		// TODO
		if (this.logging)
			console.debug("fd_read(" + fd + ", " + iovs_ptr + ", " + iovs_len + ", " + nread_ptr + ")");
		return Errno.INVAL;
	}

	fd_close = (fd) => {
		if (this.logging)
			console.debug(`fd_close(${fd})`);
		return Errno.SUCCESS;
	}

	fd_seek = (fd, offset, whence) => {
		if (this.logging)
			console.debug(`fd_seek(${fd}, ${offset}, ${whence})`);
		return Errno.INVAL;
	}

	fd_filestat_get = (fd, buf) => {
		// TODO
	}

	proc_exit = (code) => {
		
	}
}

const env = {
		jsPrint: function(arg, len) {
			console.log(readString(arg, len));
		},
		jsCreateElement: function(name, nameLen, elementType, elementTypeLen) {
      self.postMessage(["jsCreateElement", readString(name, nameLen), readString(elementType, elementTypeLen)]);
			const a = waitForAnswer("int");
			return a;
		},
		jsSetAttribute: function(element, name, nameLen, value, valueLen) {
			self.postMessage(["jsSetAttribute", element, readString(name, nameLen), readString(value, valueLen)]);
		},
		jsRemoveAttribute: function(element, name, nameLen) {
			self.postMessage(["jsRemoveAttribute", element, readString(name, nameLen)]);
		},
		getAttributeLen: function(element, name, nameLen) {
			self.postMessage(["getAttributeLen", element, readString(name, nameLen)]);
			const a = waitForAnswer("int");
			return a;
		},
		jsGetAttribute: function(element, name, nameLen, valuePtr) {
			self.postMessage(["jsGetAttribute", element, readString(name, nameLen)]);
			const a = waitForAnswer("string");
			// TODO
		},
		jsSetStyle: function(element, name, nameLen, value, valueLen) {
			self.postMessage(["jsSetStyle", element, readString(name, nameLen), readString(value, valueLen)]);
		},
		jsRemoveStyle: function(element, name, nameLen) {
			self.postMessage(["jsRemoveStyle", element, readString(name, nameLen)]);
		},
		getStyleLen: function(element, name, nameLen) {
			self.postMessage(["getStyleLen", element, readString(name, nameLen)]);
			const a = waitForAnswer("int");
			return a;
		},
		jsGetStyle: function(element, name, nameLen, valuePtr) {
			self.postMessage(["jsGetStyle", element, readString(name, nameLen)]);
			const a = waitForAnswer("string");
			// TODO
		},
		appendElement: function(parent, child) {
      self.postMessage(["appendElement", parent, child]);
		},
		/**
		 * @param {int} root
		**/
		setRoot: function(root) {
      self.postMessage(["setRoot", root]);
		},
		setText: function(element, textPtr, textLen) {
      self.postMessage(["setText", element, readString(textPtr, textLen)]);
		},
		getTextLen: function(element) {
      self.postMessage(["getTextLen", element]);
			return waitForAnswer("int");
		},
		getText: function(element, textPtr) {
			self.postMessage(["getText", element, textPtr]);
			writeBytes(textPtr, waitForAnswer("bytes"));
		},
		getValue: function(element) {
			self.postMessage(["getValue", element]);
			const a = waitForAnswer("float");
			return a;
		},
		setPos: function(element, x, y) {
			self.postMessage(["setPos", element, x, y])
		},
		setSize: function(element, w, h) {
			self.postMessage(["setSize", element, w, h]);
		},
		getWidth: function(element) {
      self.postMessage(["getWidth", element]);
      return waitForAnswer("int");
		},
		getHeight: function(element) {
      self.postMessage(["getHeight", element]);
      return waitForAnswer("int");
		},
		now: function() {
			return Date.now();
		},
		hasEvent: function() {
			self.postMessage(["hasEvent"]);
			return waitForAnswer("bool");
		},
		popEvent: function() {
			self.postMessage(["popEvent"]);
			return waitForAnswer("int");
		},
		getEventType: function(event) {
			self.postMessage(["getEventType", event]);
			return waitForAnswer("int");
		},
		getEventTarget: function(event) {
			self.postMessage(["getEventTarget", event]);
			return waitForAnswer("int");
		},
		getEventArg: function(event, idx) {
			self.postMessage(["getEventArg", event, idx]);
			return waitForAnswer("int");
		},

		// Canvas
		openContext: function(element) {
      self.postMessage(["openContext", element]);
			return waitForAnswer("int");
		},
		setColor: function(ctx, r, g, b, a) {
			self.postMessage(["setColor", ctx, r, g, b, a]);
		},
		rectPath: function(ctx, x, y, w, h) {
			self.postMessage(["rectPath", ctx, x, y, w, h]);
		},
		moveTo: function(ctx, x, y) {
			self.postMessage(["moveTo", ctx, x, y]);
		},
		lineTo: function(ctx, x, y) {
			self.postMessage(["lineTo", ctx, x, y]);
		},
		fillText: function(ctx, textPtr, textLen, x, y) {
      self.postMessage(["fillText", ctx, readString(textPtr, textLen), x, y]);
		},
		fillImage: function(ctx, img, x, y) {
			self.postMessage(["fillImage", ctx, img, x, y]);
		},
		ellipse: function(ctx, x, y, w, h) {
			self.postMessage(["ellipse", ctx, x, y, w, h]);
		},
		fill: function(ctx) {
			self.postMessage(["fill", ctx]);
		},
		stroke: function(ctx) {
			self.postMessage(["stroke", ctx]);
		},

		// Resources
		uploadImage: function(width, height, stride, isRgb, bytesPtr) {
			const size = stride * height;
			let view = new Uint8Array(obj.instance.exports.memory.buffer);
			let data = Uint8ClampedArray.from(view.slice(bytesPtr, bytesPtr + size));
			postMessage(["uploadImage", width, height, stride, isRgb, data]);
			return waitForAnswer("int");
		},

		// Network
		fetchHttp: function(urlPtr, urlLen) {
			self.postMessage(["fetchHttp", readString(urlPtr, urlLen)])
			return waitForAnswer("int");
		},
		isRequestReady: function(id) {
			self.postMessage(["isRequestReady", id]);
			return waitForAnswer("int") != 0;
		},
		readRequest: function(id, bufPtr, bufLen) {
			self.postMessage(["readRequest", id, bufLen]);
			const slice = waitForAnswer("bytes");
			writeBytes(bufPtr, slice);
			return slice.length;
		},
		yield: function() {
			// TODO: use Atomics.wait to wait until there is an event (if step is Blocking)
			//       or to wait until requestAnimationFrame is called (if step is Asynchronous)
			wait(32);
		},
		// Audio
		createSource: function(sampleRate, delay) {
			self.postMessage(["createSource", sampleRate, delay]);
			return waitForAnswer("int");
		},
		audioCopyToChannel: function(source, bufferPtr, bufferLen, channel) {
			const buffer = new Float32Array(readBuffer(bufferPtr, bufferLen).buffer);
			self.postMessage(["audioCopyToChannel", source, buffer, channel], [buffer.buffer]);
		},
		uploadAudio: function(sourceId) {
			self.postMessage(["uploadAudio", sourceId]);
		},

		stopExecution: function() {
			console.error("STOP EXECUTION!");
		},
		stopExecution: function() {
      postMessage(["stopExecution"]);
		},
	};

async function loadExtras() {
	const obj = await import("./extras.js");
	for (const key in obj.envWorker) {
		env[key] = obj.envWorker[key];
	}
}

(async function() {
	try {
		await loadExtras();
	} catch (e) {
		console.debug("No extras.js (worker)");
	}
	
	const importObject = {
		env: env,
		wasi_snapshot_preview1: new WasiImplementation(),
	};
	if (WebAssembly.instantiateStreaming) {
		obj = await WebAssembly.instantiateStreaming(fetch("zig-app.wasm"), importObject);
	} else {
		const response = await fetch("zig-app.wasm");
		obj = await WebAssembly.instantiate(await response.arrayBuffer(), importObject);
	}

  const buffer = obj.instance.exports.memory.buffer;
  self.postMessage(["setBuffer", buffer, pendingAnswer]);
	obj.instance.exports._start();
})();
