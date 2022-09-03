let obj = null;
let domObjects = [];
let canvasContexts = [];
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
	let view = new Uint8Array(obj.instance.exports.memory.buffer);
	// console.debug("read string @ " + addr + " for " + len + " bytes");
	
	return utf8Decoder.decode(view.slice(addr, addr + len));
}
const importObj = {
	env: {
		jsPrint: function(arg, len) {
			console.log(readString(arg, len));
		},
		jsCreateElement: function(name, nameLen, elementType, elementTypeLen) {
			const elem = document.createElement(readString(name, nameLen));
			const idx = domObjects.push(elem) - 1;

			elem.style.position = "absolute";
			elem.classList.add("capy-" + readString(elementType, elementTypeLen));
			elem.addEventListener("click", function(e) {
				pushEvent({
					type: 1,
					target: idx
				});
			});
			elem.addEventListener("change", function(e) {
				pushEvent({
					type: 2,
					target: idx
				});
			});

			// mouse
			elem.addEventListener("mousedown", function(e) {
				pushEvent({
					type: 3,
					target: idx,
					args: [e.button, true, e.clientX, e.clientY]
				});
			});
			elem.addEventListener("mouseup", function(e) {
				pushEvent({
					type: 3,
					target: idx,
					args: [e.button, false, e.clientX, e.clientY]
				});
			});
			elem.addEventListener("mouseleave", function(e) {
				pushEvent({
					type: 3,
					target: idx,
					args: [0, false, e.clientX, e.clientY]
				});
			});
			elem.addEventListener("mousemove", function(e) {
				pushEvent({
					type: 4,
					target: idx,
					args: [e.clientX, e.clientY]
				});
			});
			elem.addEventListener("wheel", function(e) {
				console.log(e.deltaY);
				pushEvent({
					type: 5,
					target: idx,
					args: [Math.round(e.deltaX / 100), Math.round(e.deltaY / 100)]
				});
			});

			// touch
			elem.addEventListener("touchstart", function(e) {
				pushEvent({
					type: 3,
					target: idx,
					args: [0, true, e.touches[0].clientX, e.touches[0].clientY]
				});
			});
			elem.addEventListener("touchend", function(e) {
				pushEvent({
					type: 3,
					target: idx,
					args: [0, false, e.touches[0].clientX, e.touches[0].clientY]
				});
			});
			elem.addEventListener("touchmove", function(e) {
				pushEvent({
					type: 4,
					target: idx,
					args: [e.touches[0].clientX, e.touches[0].clientY]
				});
			});
			return idx;
		},
		appendElement: function(parent, child) {
			domObjects[parent].appendChild(domObjects[child]);
		},
		setRoot: function(root) {
			document.querySelector("#application").innerHTML = "";
			document.querySelector("#application").appendChild(domObjects[root]);
			domObjects[root].style.width  = "100%";
			domObjects[root].style.height = "100%";
			rootElementId = root;
		},
		setText: function(element, textPtr, textLen) {
			const elem = domObjects[element];
			if (elem.nodeName === "INPUT") {
				elem.value = readString(textPtr, textLen);
			} else {
				elem.innerText = readString(textPtr, textLen);
			}
		},
		getTextLen: function(element) {
			const elem = domObjects[element];
			let text = "";
			if (elem.nodeName === "INPUT") text = elem.value;
			else text = elem.innerText;
			const length = new TextEncoder().encode(text).length;
			//console.log(text.length + " <= " + length);
			return length;
		},
		getText: function(element, textPtr) {
			const elem = domObjects[element];
			let text = "";
			if (elem.nodeName === "INPUT") text = elem.value;
			else text = elem.innerText;

			const encoded = new TextEncoder().encode(text);

			let view = new Uint8Array(obj.instance.exports.memory.buffer);
			for (let i = 0; i < encoded.length; i++) {
				view[textPtr + i] = encoded[i];
			}
		},
		setPos: function(element, x, y) {
			domObjects[element].style.transform = "translate(" + x + "px, " + y + "px)";
		},
		setSize: function(element, w, h) {
			domObjects[element].style.width  = w + "px";
			domObjects[element].style.height = h + "px";
			if (domObjects[element].classList.contains("capy-label")) {
				domObjects[element].style.lineHeight = h + "px";
			}
			pushEvent({
				type: 0,
				target: element
			});
		},
		getWidth: function(element) {
			return domObjects[element].clientWidth;
		},
		getHeight: function(element) {
			return domObjects[element].clientHeight;
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
			executeProgram = false;
			console.error("STOP EXECUTION!");
		},
	}
};

(async function() {
	if (WebAssembly.instantiateStreaming) {
		obj = await WebAssembly.instantiateStreaming(fetch("zig-app.wasm"), importObj);
	} else {
		const response = await fetch("zig-app.wasm");
		obj = await WebAssembly.instantiate(await response.arrayBuffer(), importObj);
	}
	obj.instance.exports._start();

	// TODO: when we're in blocking mode, avoid updating so often
	function update() {
		if (executeProgram) {
			obj.instance.exports._zgtContinue();
			requestAnimationFrame(update);
		}
	}
	//setInterval(update, 32);
	requestAnimationFrame(update);

	window.onresize = function() {
		pushEvent({ type: 0, target: rootElementId });
	};
	window.onresize(); // call resize handler atleast once, to setup layout
})();
