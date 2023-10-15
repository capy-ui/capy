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
let pendingAnswer = new SharedArrayBuffer(9);
/**
	@param {string} type The type of the answer, can only be "int"
**/
function waitForAnswer(type) {
	const WAITING = 0;
	const DONE = 1;
	
	const view = new DataView(pendingAnswer);
	view.setUint8(0, WAITING);
	while (view.getUint8(0) != DONE) {
		wait(10);
	}

	switch (type) {
		case "int":
			const int = view.getUint32(5, true) << 32 | view.getUint32(1, true);
			console.log("Received answer " + int);
			return int;
	}

	throw Error("Type invalid (" + type + ")");
}

/**
	@param {int} msecs Time to wait in milliseconds
**/
function wait(msecs) {
	const start = Date.now();
	while (Date.now() >= start + msecs) {
		// Wait.
	}

	return;
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
			return pendingEvents.length > 0;
		},
		popEvent: function() {
			if (pendingEvents.length > 0) {
				return pendingEvents.shift();
			} else {
				console.error("Popping event even though none is available!");
			}
		},
		getEventType: function(event) {
			return events[event].type;
		},
		getEventTarget: function(event) {
			if (events[event].target === undefined) {
				console.error("Tried getting the target of a global event");
			}
			return events[event].target;
		},
		getEventArg: function(event, idx) {
			if (events[event].args === undefined || events[event].args[idx] === undefined) {
				console.error("Tried getting non-existent arg:" + idx);
			}
			return events[event].args[idx];
		},

		// Canvas
		openContext: function(element) {
			const canvas = domObjects[element];
			canvas.width = window.devicePixelRatio * canvas.clientWidth;
			canvas.height = window.devicePixelRatio * canvas.clientHeight;

			for (ctxId in canvasContexts) {
				if (canvasContexts[ctxId].owner === element) {
					canvasContexts[ctxId].clearRect(0, 0, canvas.width, canvas.height);
					return ctxId;
				}
			}
			const ctx = canvas.getContext("2d");
			ctx.owner = element;
			ctx.lineWidth = 2.5;
			ctx.beginPath();
			return canvasContexts.push(ctx) - 1;
		},
		setColor: function(ctx, r, g, b, a) {
			canvasContexts[ctx].fillStyle = "rgba(" + r + "," + g + "," + b + "," + a + ")";
			canvasContexts[ctx].strokeStyle = canvasContexts[ctx].fillStyle;
		},
		rectPath: function(ctx, x, y, w, h) {
			canvasContexts[ctx].rect(x, y, w, h);
		},
		moveTo: function(ctx, x, y) {
			canvasContexts[ctx].moveTo(x, y);
		},
		lineTo: function(ctx, x, y) {
			canvasContexts[ctx].lineTo(x, y);
		},
		fillText: function(ctx, textPtr, textLen, x, y) {
			const text = readString(textPtr, textLen);
			canvasContexts[ctx].textAlign = "left";
			canvasContexts[ctx].textBaseline = "top";
			canvasContexts[ctx].fillText(text, x, y);
		},
		fillImage: function(ctx, img, x, y) {
			const canvas = canvasContexts[ctx];
			const image = resources[img];
			if (!image.imageDatas[ctx]) {
				image.imageDatas[ctx] = canvas.createImageData(image.width, image.height);
				const data = image.imageDatas[ctx].data;
				const Bpp = image.stride / image.width; // source bytes per pixel
				for (let y = 0; y < image.height; y++) {
					for (let x = 0; x < image.width; x++) {
						data[y*image.width*4+x*4+0] = image.bytes[y*image.stride+x*Bpp+0];
						data[y*image.width*4+x*4+1] = image.bytes[y*image.stride+x*Bpp+1];
						data[y*image.width*4+x*4+2] = image.bytes[y*image.stride+x*Bpp+2];
						if (!image.isRgb) {
							data[y*image.width*4+x*4+3] = image.bytes[y*image.stride+x*Bpp+3];
						} else {
							data[y*image.width*4+x*4+3] = 0xFF;
						}
					}
				}
				image.bytes = undefined; // try to free up some space
				resources[img] = image;
			}
			canvas.putImageData(image.imageDatas[ctx], x, y);
		},
		fill: function(ctx) {
			canvasContexts[ctx].fill();
			canvasContexts[ctx].beginPath();
		},
		stroke: function(ctx) {
			canvasContexts[ctx].stroke();
			canvasContexts[ctx].beginPath();
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

		stopExecution: function() {
      postMessage(["stopExecution"]);
		},
	};

console.log("WEB WORKER RUN");

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
