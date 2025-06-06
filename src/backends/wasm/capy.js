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

let audioSources = [];

let audioContext = new AudioContext({
	latencyHint: "balanced",
});
let lastAudioUpdateTime = 0;
/**
	@type SharedArrayBuffer
**/
let pendingAnswer = undefined;

/**
	Draw commands scheduled for the next frame
**/
let drawCommands = [];

function pushEvent(evt) {
	const eventId = events.push(evt);
	pendingEvents.push(eventId - 1);
}

async function pushAnswer(type, value) {
	// Convert booleans to integers
	if (value === true) value = 1;
	if (value === false) value = 0;
	
	if (type == "int" && typeof value !== "number") {
		throw Error("Type mismatch, got " + (typeof value));
	}
	if (type == "float" && typeof value !== "number") {
		throw Error("Type mismatch, got " + (typeof value));
	}
	if (type == "bytes" && !(value instanceof Uint8Array)) {
		throw Error("Type mismatch, got " + (typeof value));
	}
	if (type == "string") {
		throw Error("Type mismatch");
	}

	const WAITING = 0;
	const DONE = 1;
	const view = new Int32Array(pendingAnswer);
	while (view[0] != WAITING) {
		// throw Error("Expected waiting state");
		await wait(24);
		// console.log("Await waiting state");
	}

	if (type == "int") {
		const left = value & 0xFFFFFFFF;
		const right = value >> 32;
		view[1] = left;
		view[2] = right;
	} else if (type == "float") {
		new DataView(view.buffer).setFloat64(0x4, value);
	} else if (type == "bytes") {
		const length = value.length;
		view[1] = length;
		new Uint8Array(view.buffer).set(value, 0x8);
	}
	view[0] = DONE;
	if (Atomics.notify(view, 0) != 1) {
		console.warn("Expected 1 agent to be awoken.");
	}
}

async function wait(msecs) {
	const promise = new Promise((resolve, reject) => {
		setTimeout(resolve, msecs);
	});
	return promise;
}

class SoundBuffer {
		constructor(ctx, sampleRate, bufferSize, debug) {
			this.ctx = ctx;
			this.sampleRate = sampleRate;
			this.bufferSize = bufferSize || 6;
			this.debug = debug;

			this.chunks = [];
			this.isPlaying = true;
			this.startTime = true;
			this.lastChunkOffset = 0;
		}

    createChunk(chunk)  {
				/**
					@type {AudioBuffer}
				**/
        var audioBuffer = this.ctx.createBuffer(2, chunk[0].length, this.sampleRate);
        // audioBuffer.getChannelData(0).set(chunk[0]);
        // audioBuffer.getChannelData(1).set(chunk[1]);
				audioBuffer.copyToChannel(chunk[0], 0);
				audioBuffer.copyToChannel(chunk[1], 1);
        var source = this.ctx.createBufferSource();
        source.buffer = audioBuffer;
        source.connect(this.ctx.destination);
        source.onended = (e) => { 
            this.chunks.splice(this.chunks.indexOf(source),1);
            if (this.chunks.length == 0) {
                this.isPlaying = false;
                this.startTime = 0;
                this.lastChunkOffset = 0;
            }
        };

        return source;
    }

    log(data) {
        if (this.debug) {
            console.log(new Date().toUTCString() + " : " + data);
        }
    }

		/**
			@param {Float32Array[]} data
		**/
    addChunk(data) {
        if (this.isPlaying && (this.chunks.length > this.bufferSize)) {
            this.log("chunk discarded");
            return; // throw away
        } else if (this.isPlaying && (this.chunks.length <= this.bufferSize)) { // schedule & add right now
            this.log("chunk accepted");
            let chunk = this.createChunk(data);
            chunk.start(this.startTime + this.lastChunkOffset);
            this.lastChunkOffset += chunk.buffer.duration;
            this.chunks.push(chunk);
        } else if ((this.chunks.length < (this.bufferSize / 2)) && !this.isPlaying) {  // add & don't schedule
            this.log("chunk queued");
            let chunk = this.createChunk(data);
            this.chunks.push(chunk);
        } else  { // add & schedule entire buffer
            this.log("queued chunks scheduled");
            this.isPlaying = true;
            let chunk = this.createChunk(data);
            this.chunks.push(chunk);
            this.startTime = this.ctx.currentTime;
            this.lastChunkOffset = 0;
            for (let i = 0;i<this.chunks.length;i++) {
                let chunk = this.chunks[i];
                chunk.start(this.startTime + this.lastChunkOffset);
                this.lastChunkOffset += chunk.buffer.duration;
            }
        }
    }
}

let env = {
		jsCreateElement: function(name, elementType) {
			const elem = document.createElement(name);
			const idx = domObjects.push(elem) - 1;

			if (elementType === "slider") {
				elem.type = "range";
			}

			elem.style.position = "absolute";
			elem.classList.add("capy-"  + elementType);
			elem.addEventListener("click", function(e) {
				if (elem.nodeName == "BUTTON") {
					pushEvent({
						type: 1,
						target: idx
					});
				}
			});
			elem.addEventListener("change", function(e) {
				pushEvent({
					type: 2,
					target: idx
				});
			});
			elem.addEventListener("input", (e) => {
				if (elementType === "slider") {
					pushEvent({
						type: 7,
						target: idx
					});
				}
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
					//args: [Math.round(e.deltaX / 100), Math.round(e.deltaY / 100)]
					// the way it works is very browser and OS dependent so just assume
					// we scrolled 1 'tick'
					args: [1 * Math.sign(e.deltaX), 1 * Math.sign(e.deltaY)]
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
		jsSetAttribute: function(element, name, value) {
			domObjects[element].setAttribute(name, value);
		},
		jsRemoveAttribute: function(element, name) {
			domObjects[element].removeAttribute(name);
		},
		getAttributeLen: function(element, name) {
			return domObjects[element].getAttribute(name).length;
		},
		getAttribute: function(element, name) {
			const attr = domObjects[element].getAttribute(name);
			// TODO: send
		},
		jsSetStyle: function(element, name, value) {
			domObjects[element].style[name] = value;
		},
		jsRemoveStyle: function(element, name) {
			domObjects[element].style[name] = null;
		},
		getStyleLen: function(element, name) {
			return domObjects[element].style[name].length;
		},
		getStyle: function(element, name) {
			const attr = domObjects[element].style[name];
			// TODO: send
		},
		getValue: function(element) {
			return Number.parseFloat(domObjects[element].value);
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
			window.onresize(); // call resize handler atleast once, to setup layout
		},
		setText: function(element, text) {
			const elem = domObjects[element];
			if (elem.nodeName === "INPUT") {
				elem.value = text;
			} else {
				elem.innerText = text;
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
			return encoded;
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
			return domObjects[element].width || domObjects[element].clientWidth;
		},
		getHeight: function(element) {
			return domObjects[element].height || domObjects[element].clientHeight;
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

			for (let ctxId in canvasContexts) {
				if (canvasContexts[ctxId].owner === element) {
					// canvasContexts[ctxId].clearRect(0, 0, canvas.width, canvas.height);
					return Number.parseInt(ctxId);
				}
			}
			const ctx = canvas.getContext("2d");
			ctx.owner = element;
			ctx.lineWidth = 2.5;
			ctx.beginPath();
			return canvasContexts.push(ctx) - 1;
		},
		setColor: function(ctx, r, g, b, a) {
			drawCommands.push([ctx, "setColor", r, g, b, a]);
		},
		rectPath: function(ctx, x, y, w, h) {
			drawCommands.push([ctx, "rectPath", x, y, w, h]);
		},
		moveTo: function(ctx, x, y) {
			drawCommands.push([ctx, "moveTo", x, y]);
		},
		lineTo: function(ctx, x, y) {
			drawCommands.push([ctx, "lineTo", x, y]);
		},
		fillText: function(ctx, text, x, y) {
			drawCommands.push([ctx, "fillText", text, x, y]);
		},
		fillImage: function(ctx, img, x, y) {
			drawCommands.push([ctx, "fillImage", img, x, y]);
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
		ellipse: function(ctx, x, y, w, h) {
			drawCommands.push([ctx, "ellipse", x + w / 2, y + h / 2, w / 2, h / 2]);
		},
		fill: function(ctx) {
			drawCommands.push([ctx, "fill"]);
		},
		stroke: function(ctx) {
			drawCommands.push([ctx, "stroke"]);
		},

		// Resources
		uploadImage: function(width, height, stride, isRgb, data) {
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
		fetchHttp: function(url) {
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
			return networkRequestsCompletion[id] ? 1 : 0;
		},
		readRequest: function(id, bufLen) {
			if (networkRequestsCompletion[id] === false) return 0;

			const buffer = networkRequests[id];
			const idx = networkRequestsReadIdx[id];

			const view = new Uint8Array(buffer);
			const slice = view.slice(idx, idx + bufLen);
			networkRequestsReadIdx[id] += slice.length;
			return slice;
		},

		// Audio
		createSource: function(sampleRate, delay) {
	    const frameCount = sampleRate * delay;
	    const audioBuffer = audioContext.createBuffer(2, frameCount, sampleRate);

	    const source = new AudioBufferSourceNode(audioContext, {
	      buffer: audioBuffer,
	    });
			const audioSource = {
				source: source,
				frameCount: frameCount,
				nextUpdate: audioContext.currentTime,
				soundBuffer: new SoundBuffer(audioContext, 44100, 6, true),
			};
			return audioSources.push(audioSource) - 1;
		},
		audioCopyToChannel: function(sourceId, buffer, channel) {
			const source = audioSources[sourceId];
			if (channel == 0) {
				source.left = buffer;
			} else {
				source.right = buffer;
			}
		},
		uploadAudio: function(sourceId) {
			const source = audioSources[sourceId];
			const latency = 0.1;
			source.nextUpdate += latency;
			source.soundBuffer.addChunk([source.left, source.right]);
		},

		stopExecution: function() {
			executeProgram = false;
			console.error("STOP EXECUTION!");
		},
};

async function loadExtras() {
	const obj = await import("./extras.js");
	for (const key in obj.env) {
		env[key] = obj.env[key];
	}
}


(async function() {
	if (!window.Worker) {
		alert("Capy requires Web Workers until Zig supports async");
	}

	try {
		await loadExtras();
	} catch (e) {
		console.debug("No extras.js");
	}
	
	const wasmWorker = new Worker("capy-worker.js");
	wasmWorker.postMessage("test");
	wasmWorker.onmessage = (e) => {
		const name = e.data[0];
		if (name === "setBuffer") {
			pendingAnswer = e.data[2];
		} else if (name === "stopExecution") {
			wasmWorker.terminate();
		} else {
			const value = env[name].apply(null, e.data.slice(1));
			if (value !== undefined) {
				let answerType = "int";
				if (name === "getValue") {
					answerType = "float";
				}
				if (value instanceof Uint8Array)
					answerType = "bytes";
				pushAnswer(answerType, value);
			}
		}
	};

	// TODO: when we're in blocking mode, avoid updating so often
	function update() {
		// Fulfill draw commands
		for (const command of drawCommands) {
			const ctx = canvasContexts[command[0]];
			
			switch (command[1]) {
				case "moveTo":
					ctx.moveTo(command[2], command[3]);
					break;
				case "lineTo":
					ctx.lineTo(command[2], command[3]);
					break;
				case "rectPath":
					ctx.rect(command[2], command[3], command[4], command[5]);
					break;
				case "fillText":
					ctx.textAlign = "left"; ctx.textBaseline = "top";
					ctx.fillText(command[2], command[3], command[4]);
					break;
				case "ellipse":
					ctx.ellipse(command[2], command[3], command[4], command[5], 0, 0, 2 * Math.PI);
					break;
				case "setColor":
					const r = command[2];
					const g = command[3];
					const b = command[4];
					const a = command[5];
					ctx.fillStyle = "rgba(" + r + "," + g + "," + b + "," + a + ")";
					ctx.strokeStyle = ctx.fillStyle;
					break;
				case "stroke":
					ctx.stroke();
					ctx.beginPath();
					break;
				case "fill":
					ctx.fill();
					ctx.beginPath();
					break;
			}
		}
		drawCommands = [];

		// send window tick event
		pushEvent({
			type: 8,
			args: [],
		});

		requestAnimationFrame(update);
	}
	//setInterval(update, 32);
	requestAnimationFrame(update);

	function audioUpdate() {
		// Audio
		const latency = 0.1; // The latency we want, in seconds.
		if (audioContext.currentTime > lastAudioUpdateTime + latency) {
			// Trigger an event so the audio buffer is refilled
			pushEvent({
				type: 6,
				args: [],
			});
			lastAudioUpdateTime = audioContext.currentTime - 0.01;
		}
	}
	setInterval(audioUpdate, 50);

	window.onresize = function() {
		pushEvent({ type: 0, target: rootElementId });
	};
	window.onclick = function() {
		audioContext.resume();
	}
})();
