let obj = null;
let pendingEvents = [];
let networkRequests = [];
let networkRequestsCompletion = [];
let networkRequestsReadIdx = [];
let resources = [];
let events = [];
let executeProgram = true;
let rootElementId = -1;

function pushEvent(evt) {
	const eventId = events.push(evt);
	pendingEvents.push(eventId - 1);
}

function readString(addr, len) {
	addr = addr >>> 0; // convert from i32 to u32
	len = len >>> 0;

	let utf8Decoder = new TextDecoder();
	// let view = new Uint8Array(obj.instance.exports.memory.buffer);
	let view = new Uint8Array(env.memory.buffer);
	// console.debug("read string @ " + addr + " for " + len + " bytes");
	
	return utf8Decoder.decode(view.slice(addr, addr + len));
}

// 1 byte for making and 8 bytes for data (64 bits)
let pendingAnswer = new SharedArrayBuffer(12);
/**
	@param {string} type The type of the answer, can only be "int"
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

const memory = new WebAssembly.Memory({
	initial: 20,
	maximum: 100,
	// shared: true, // NOT SUPPORTED ON FIREFOX
});
const env = {
		memory: memory,
		jsPrint: function(arg, len) {
			console.log(readString(arg, len));
		},
		jsCreateElement: function(name, nameLen, elementType, elementTypeLen) {
      self.postMessage(["jsCreateElement", name, nameLen, elementType, elementTypeLen]);
			const a = waitForAnswer("int");
			return a;
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
			return resources.push({
				type: 'image',
				width: width,
				height: height,
				stride: stride,
				rgb: isRgb != 0,
				bytes: data,
				imageDatas: {},
			}) - 1;
		},

		// Network
		fetchHttp: function(urlPtr, urlLen) {
			const url = readString(urlPtr, urlLen);
			const id = networkRequests.length;
			const promise = fetch(url).then(response => response.arrayBuffer()).then(response => {
				networkRequestsCompletion[id] = true;
				networkRequests[id] = response;
			});
			networkRequestsCompletion.push(false);
			networkRequestsReadIdx.push(0);
			return networkRequests.push(promise) - 1;
		},
		isRequestReady: function(id) {
			return networkRequestsCompletion[id];
		},
		readRequest: function(id, bufPtr, bufLen) {
			if (networkRequestsCompletion[id] === false) return 0;

			const buffer = networkRequests[id];
			const idx = networkRequestsReadIdx[id];

			const view = new Uint8Array(buffer);
			const slice = view.slice(idx, idx + bufLen);
			const memoryView = new Uint8Array(obj.instance.exports.memory.buffer);
			for (let i = 0; i < slice.length; i++) {
				memoryView[bufPtr + i] = slice[i];
			}
			networkRequestsReadIdx[id] += slice.length;

			return slice.length;
		},
		yield: function() {
			// TODO: use Atomics.wait to wait until there is an event (if step is Blocking)
			//       or to wait until requestAnimationFrame is called (if step is Asynchronous)
			wait(32);
		},
		stopExecution: function() {
      postMessage(["stopExecution"]);
		},
	};

(async function() {
	const importObject = {
		env: env,
	};
	if (WebAssembly.instantiateStreaming) {
		obj = await WebAssembly.instantiateStreaming(fetch("zig-app.wasm"), importObject);
	} else {
		const response = await fetch("zig-app.wasm");
		obj = await WebAssembly.instantiate(await response.arrayBuffer(), importObject);
	}

  // const buffer = obj.instance.exports.memory.buffer;
  self.postMessage(["setBuffer", memory.buffer, pendingAnswer]);
	obj.instance.exports._start();
})();
