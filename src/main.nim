
import ./sdl2, nimPNG, math

proc loadTexture(path: string): TexturePtr
proc processAudio(udata: pointer, stream: UncheckedArray[int16],
    bytes: cint): void {.cdecl.}

const
  Debug = false
  TalkThreshold = 3000
  CoyoteTime = 200
  WindowWidth = 640
  WindowHeight = 360
  SpritePaths = [
    "assets/popcat1.png",
    "assets/popcat2.png",
    "assets/popcat3.png",
  ]

init(INIT_VIDEO + INIT_AUDIO)
showCursor(false)

var
  window = createWindow("nim2br", 0, 0, WindowWidth, WindowHeight, 0)
  renderer = createRenderer(window, -1, 0)
  quit = false
  sprites: seq[TexturePtr] = @[]
  frame = 0
  averageGain = 0.0
  wasTalking = false
  startedTalkingAt: uint64 = 0
  stoppedTalkingAt: uint64 = 0

for path in SpritePaths: sprites.add loadTexture(path)

var
  wantedAudioSpec = AudioSpec(
    format: 0x8010,
    channels: 1,
    samples: 1024,
    callback: processAudio)
  audioSpec = AudioSpec()

let audioDeviceID = openAudioDevice(nil, 1, addr wantedAudioSpec,
    addr audioSpec, 0)

echo repr audioSpec

audioDeviceID.pauseAudioDevice(0)

while not quit:
  var e = defaultEvent
  while e.pollEvent():
    case e.kind:
    of QuitEvent:
      quit = true
    else:
      discard

  let
    isTalking = averageGain > TalkThreshold
    ticks = getTicks()

  if not wasTalking and isTalking:
    startedTalkingAt = ticks
  if wasTalking and not isTalking:
    stoppedTalkingAt = ticks
  wasTalking = isTalking

  if isTalking or ticks - stoppedTalkingAt < CoyoteTime:
    frame = 1 + ticks.int div 250 mod 2
  else:
    frame = 0

  renderer.setDrawColor(0, 255, 0, 0)
  renderer.clear()
  block:
    let sprite = sprites[frame]
    var w, h: cint
    sprite.queryTexture(nil, nil, addr w, addr h)
    let scale = WindowHeight*0.90 * 1/h.float
    var dst = rectf(
      (WindowWidth-w.float*scale)/2,
      WindowHeight - h.float*scale + h.float*0.05*scale,
      w.float * scale, h.float * scale)
    let
      t = (sin(getTicks().float/1000.0 * PI)+1)/2
      angle = (1.0 - t) * -5 + t * 5
      center = pointf(w.float/2 * scale, h.float * scale)
    renderer.copyExF(sprites[frame], nil, dst, angle, addr center, SDL_FLIP_NONE)
  renderer.present()

  when Debug: echo averageGain

# -----------------------------------------------------------------------------
proc loadTexture(path: string): TexturePtr =
  let png = loadPNG32(path)
  if png.isNil:
    echo "failed to load png: " & path
    return nil

  let surface = createRGBSurfaceFrom(addr png.data[0],
    png.width.cint, png.height.cint, 32, png.width.cint*4,
    0xff.uint32, 0xff00.uint32, 0xff0000.uint32, 0xff000000.uint32)
  if surface.isNil:
    echo "Failed to create surface: " & $path & ": " & $getError()
    return nil

  result = createTextureFromSurface(renderer, surface)
  freeSurface(surface)
  if result.isNil:
    echo "Failed to create texture: " & $path & ": " & $getError()
  else:
    echo "Texture created: " & path

# -----------------------------------------------------------------------------
proc processAudio(udata: pointer, stream: UncheckedArray[int16],
    bytes: cint): void {.cdecl.} =
  # echo "audio process"
  let samples = bytes div 2
  var
    count: float64 = 0
    accum: float64 = 0
  for i in 0..<samples:
    if stream[i] != 0:
      count += 1
      accum += stream[i].float64.abs
  if count > 0:
    averageGain = accum / count
  else:
    averageGain = 0.0
