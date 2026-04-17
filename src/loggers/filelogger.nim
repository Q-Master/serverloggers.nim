from logging import nil
import std/[times, os]
import ./[serverlogger]
import ../private/[util]


when useAsync:
  import std/[asyncdispatch, asyncfile]

when useThreads:
  import std/[locks, atomics]


type
  FileLoggerRotations* = enum
    FL_NONE         #  no rotation at all
    FL_HOUR         #  rotation will be done every hour
    FL_DAY          #  rotation will be done every midnight
    FL_WEEK         #  rotation will be done every monday midnight

  FileLoggerImpl = ref object of RootObj
    fileName: string
    rotated: FileLoggerRotations
    lastRotated: Time
    maxRotations: int
    when useAsync:
      fd: AsyncFile
      alreadyRotating: Future[void]
    else:
      when useThreads:
        fLock: Lock
        rotatingCond: Cond
        fd: File
      else:
        fd: File

  FileLogger* = ref object of ServerLogger
    impl: FileLoggerImpl


when defined(posix):
  import std/[posix, oserrors]

  type
    StatXTimeStamp* {.importc: "struct statx_timestamp", header: "<sys/stat.h>", final, pure.} = object ## struct statx_timestamp
      tv_sec*: int64  ## Seconds.
      tv_nsec*: clong  ## Nanoseconds.
      pad {.importc: "__pad".}: uint32

    StatX* {.importc: "struct statx", header: "<sys/stat.h>", final, pure.} = object ## struct statx
      stx_mask*: uint32
      stx_blksize*: uint32
      stx_attributes*: uint64
      stx_nlink*: uint32
      stx_uid*: uint32
      stx_gid*: uint32
      stx_mode*: uint32
      pad0 {.importc: "__pad0".}: uint16
      stx_ino*: uint64
      stx_size*: uint64
      stx_blocks*: uint64
      stx_attributes_mask*: uint64
      stx_atime*: StatXTimeStamp
      stx_btime*: StatXTimeStamp
      stx_ctime*: StatXTimeStamp
      stx_mtime*: StatXTimeStamp
      stx_rdev_major*: uint32
      stx_rdev_minor*: uint32
      stx_dev_major*: uint32
      stx_dev_minor*: uint32
      pad1 {.importc: "__pad1".}: array[14, uint64]
  const STATX_BASIC_STATS = cuint(0x7ff)
  const STATX_BTIME = cuint(0x800)
  const AT_FDCWD = cint(-100)
  const AT_SYMLINK_NOFOLLOW = cint(0x100)


  proc statx*(a1: cint, a2: cstring, a3: cint, a4: cuint, a5: var StatX): cint {.importc, header: "<sys/stat.h>".}

  proc toTime(ts: StatXTimeStamp): times.Time {.inline.} =
    result = initTime(ts.tv_sec, ts.tv_nsec)

  proc getCreationTime*(file: string): times.Time =
    var res: StatX = default(StatX)
    if statx(AT_FDCWD, file, AT_SYMLINK_NOFOLLOW, STATX_BASIC_STATS or STATX_BTIME, res) < 0'i32: raiseOSError(osLastError(), file)
    result = res.stx_btime.toTime


proc newFileLogger*(
  fileName: string,
  rotated: FileLoggerRotations = FL_NONE,
  level = logging.lvlDebug,
  fmtStr = DEFAULT_FORMAT,
  maxRotations: int = 1
): FileLogger =
  result.new
  result.impl.new
  result.impl.fileName = fileName
  result.impl.rotated = rotated
  result.impl.maxRotations = maxRotations
  result.impl.fd = nil
  when useAsync:
    result.impl.alreadyRotating = nil
  else:
    when useThreads:
      result.impl.rotatingCond.initCond()
      result.impl.fLock.initLock()
  result.initLogger(level, fmtStr)


proc rollover(self: FileLogger) =
  if self.impl.maxRotations > 0:
    for i in countdown(self.impl.maxRotations-1, 1):
      let sfn = self.impl.fileName & "." & $i
      let dfn = self.impl.fileName & "." & $(i+1)
      if fileExists(sfn):
        moveFile(sfn, dfn)
    let dfn = self.impl.fileName & ".1"
    moveFile(self.impl.fileName, dfn)
  else:
    # if maxRotations is 0 and enabled rolling, just remove the source file
    removeFile(self.impl.fileName)


when useAsync:
  proc rotate(self: FileLogger) {.async.} =
    if not self.impl.alreadyRotating.isNil and not self.impl.alreadyRotating.finished:
      # prohibit rotating when already rotating
      await self.impl.alreadyRotating
    else:
      # do rotations
      self.impl.alreadyRotating = newFuture[void]()
      if not self.impl.fd.isNil:
        self.impl.fd.close()
      self.rollover()
      self.impl.fd = openAsync(self.impl.fileName, fmAppend)
      self.impl.lastRotated = getTime()
      self.impl.alreadyRotating.complete()


  proc checkRotate(self: FileLogger) {.async.} =
    let currTime = getTime()
    case self.impl.rotated
    of FL_NONE:
      discard
    of FL_HOUR:
      if (currTime-self.impl.lastRotated).inHours >= 1:
        await self.rotate()
    of FL_DAY:
      if (currTime-self.impl.lastRotated).inDays >= 1:
        await self.rotate()
    of FL_WEEK:
      if (currTime-self.impl.lastRotated).inWeeks >= 1:
        await self.rotate()


  method open*(self: FileLogger, name: string) =
    if self.impl.rotated != FL_NONE:
      try:
        self.impl.lastRotated = getCreationTime(self.impl.fileName)
      except:
        self.impl.lastRotated = getTime()

    proc realOpen() {.async.} =
      await self.checkRotate()
      if self.impl.fd.isNil:
        self.impl.fd = openAsync(self.impl.fileName, fmAppend)
    waitFor(realOpen())
    self.install(name)


  method log*(logger: FileLogger, level: logging.Level, args: varargs[string, `$`]) =
    if level >= logger.levelThreshold:
      let msg = logger.buildMessage(level, args) & "\n"
      proc realsend() {.async.} =
        await logger.checkRotate()
        await write(logger.impl.fd, msg)
      waitFor(realsend())

else:
  proc rotate(self: FileLogger) =
    if not self.impl.fLock.tryAcquire():
      self.impl.rotatingCond.wait(self.impl.fLock)
    else:
      if not self.impl.fd.isNil:
        self.impl.fd.close()
      # do rotations
      self.rollover()
      self.impl.fd = open(self.impl.fileName, fmAppend)
      self.impl.lastRotated = getTime()
      self.impl.rotatingCond.broadcast()
      self.impl.fLock.release()


  proc checkRotate(self: FileLogger) =
    let currTime = getTime()
    case self.impl.rotated
    of FL_NONE:
      discard
    of FL_HOUR:
      if (currTime-self.impl.lastRotated).inHours >= 1:
        self.rotate()
    of FL_DAY:
      if (currTime-self.impl.lastRotated).inDays >= 1:
        self.rotate()
    of FL_WEEK:
      if (currTime-self.impl.lastRotated).inWeeks >= 1:
        self.rotate()


  method open*(self: FileLogger, name: string) =
    if self.impl.rotated != FL_NONE:
      try:
        self.impl.lastRotated = getCreationTime(self.impl.fileName)
      except:
        self.impl.lastRotated = getTime()
    self.checkRotate()
    if self.impl.fd.isNil:
      self.impl.fd = open(self.impl.fileName, fmAppend)
    self.install(name)


  method log*(logger: FileLogger, level: logging.Level, args: varargs[string, `$`]) =
    if level >= logger.levelThreshold:
      logger.checkRotate()
      let msg = logger.buildMessage(level, args) & "\n"
      write(logger.impl.fd, msg)


method close*(self: FileLogger) =
  self.impl.fd.close()
  self.deinstall()


proc clone*(self: FileLogger): FileLogger =
  result.new
  self.clone(result)
  result.impl = self.impl
