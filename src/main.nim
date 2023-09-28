import ./sdl2, nimPNG, math, parsecfg, strutils, os

proc loadTexture(path: string): TexturePtr
proc processAudio(udata: pointer, stream: UncheckedArray[int16],
    bytes: cint): void {.cdecl.}

const defaultConfig = """
[ Debug ]
Printing = true

[ Audio ]
TalkThreshold = 3000
TalkCooldown = 200

[ Animation ]
BlinkDuration = 100
BlinkInterval = 2000

[ Window ]
WindowWidth = 640
WindowHeight = 360

[ Animation Frames ]
Quiet = "assets/popcat1.png"
EyeBlink = "assets/popcatblinks.png"
Talk1 = "assets/popcat2.png"
Talk2 = "assets/popcat3.png"

[ Emotions ]
Amused = "assets/amused.png"
Good = "assets/good.png"
Bad = "assets/bad.png"
"""

var
  prefix = getCurrentDir()
  configPath = prefix & "/config.cfg"
  keyIsPressed = false

let
  params = commandLineParams()

if params.len > 0:
  prefix = params[0]
  configPath = prefix & "/config.cfg"
  echo "loading config:\n  ", configPath
else:
  echo "loading config:\n  ", configPath
  if not fileExists(configPath):
    prefix = getAppDir()
    configPath = prefix & "/config.cfg"
    echo "config.cfg not found. trying app dir:\n  ", configPath

if not fileExists(configPath):
  echo "config.cfg not found! writing default and exiting..."
  try:
    writeFile(configPath, defaultConfig)
  except IOError:
    echo "couldn't write default config!"
    discard
  quit(-1)

let
  cfg = loadConfig(configPath)
  debugPrints = cfg.getSectionValue("Debug", "Printing") == "true"
  talkThreshold = cfg.getSectionValue("Audio", "TalkThreshold", "1000").parseInt()
  talkCooldown = cfg.getSectionValue("Audio", "TalkCooldown", "200").parseInt()
  blinkDuration = cfg.getSectionValue("Animation", "BlinkDuration", "100").parseInt()
  blinkInterval = cfg.getSectionValue("Animation", "BlinkInterval", "2000").parseInt()
  windowWidth = cfg.getSectionValue("Window", "WindowWidth", "640").parseInt()
  windowHeight = cfg.getSectionValue("Window", "WindowHeight", "480").parseInt()
  spritePaths = [
    prefix & "/" & cfg.getSectionValue("Animation Frames", "Quiet"),
    prefix & "/" & cfg.getSectionValue("Animation Frames", "EyeBlink"),
    prefix & "/" & cfg.getSectionValue("Animation Frames", "Talk1"),
    prefix & "/" & cfg.getSectionValue("Animation Frames", "Talk2"),
    prefix & "/" & cfg.getSectionValue("Animation Frames", "Talk3"),
    prefix & "/" & cfg.getSectionValue("Emotions", "Amused"),
    prefix & "/" & cfg.getSectionValue("Emotions", "Good"),
    prefix & "/" & cfg.getSectionValue("Emotions", "Bad"),
  ]
  waggleMaxAngle = cfg.getSectionValue("Waggle", "MaxAngle", "5.0").parseFloat()
  wagglePeriod = cfg.getSectionValue("Waggle", "Period", "1.0").parseFloat()

init(INIT_VIDEO + INIT_AUDIO)
showCursor(false)

var
  window = createWindow("nim2br", 0, 0, windowWidth.cint, windowHeight.cint, 0)
  renderer = createRenderer(window, -1, 0)
  quit = false
  sprites: seq[TexturePtr] = @[]
  frame = 0
  averageGain = 0.0
  wasTalking = false
  startedTalkingAt: uint64 = 0
  stoppedTalkingAt: uint64 = 0
  lastBlinkTime: uint32 = 0


for path in spritePaths: sprites.add loadTexture(path)

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
    of KeyDown:
      case e.key.keysym.sym
      of K_1:
        frame = 5 # frame for Amused
        keyIsPressed = true
      of K_2:
        frame = 6 # frame for Good
        keyIsPressed = true
      of K_3:
        frame = 7 # frame for Bad
        keyIsPressed = true
      else:
        discard
    of KeyUp:
      case e.key.keysym.sym
      of K_1, K_2, K_3:
        frame = 0 # Back to default frame
        keyIsPressed = false
      else:
        discard
    else:
      discard

  if not keyIsPressed:
    let
      isTalking = averageGain > talkThreshold.float
      ticks = getTicks()

    if not wasTalking and isTalking:
      startedTalkingAt = ticks
    if wasTalking and not isTalking:
      stoppedTalkingAt = ticks
    wasTalking = isTalking

    let
      currentTime = getTicks()
      timeSinceLastBlink = currentTime - lastBlinkTime

    if isTalking or ticks - stoppedTalkingAt < talkCooldown.uint32:
      frame = 2 + ticks.int div 250 mod 3
    elif timeSinceLastBlink >= blinkInterval.uint32:
        if timeSinceLastBlink - blinkDuration.uint32 <= blinkInterval.uint32:
          frame = 1
        else:
          lastBlinkTime = currentTime
    else:
      frame = 0

  renderer.setDrawColor(0, 255, 0, 0)
  renderer.clear()
  block:
    let sprite = sprites[frame]
    var w, h: cint
    sprite.queryTexture(nil, nil, addr w, addr h)
    let scale = windowHeight.float*0.90 * 1/h.float
    var dst = rectf(
      (windowWidth.float - w.float*scale)/2,
      windowHeight.float - h.float*scale + h.float*0.05*scale,
      w.float * scale, h.float * scale)
    let
      t = (sin(getTicks().float/1000.0 * 1/wagglePeriod * PI)+1)/2
      angle = (1.0 - t) * -(waggleMaxAngle) + t * (waggleMaxAngle)
      center = pointf(w.float/2 * scale, h.float * scale)
    renderer.copyExF(sprites[frame], nil, dst, angle, addr center, SDL_FLIP_NONE)
  renderer.present()

  if debugPrints: echo averageGain

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
