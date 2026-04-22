from logging import nil
import std/[os, nativesockets, strutils]
import ../private/[formatter, tagger, util]


type
    ServerLogger* = ref object of logging.Logger
      formatter: LoggerFormatter
      tagger: LoggerTagger
      name: string
      hostName: string
      when useThreads:
        threadId: int32 = -1
      processId: int32 = -1
      processName: string = ""


proc getProcessNameByPid(pid: int): string =
  when defined(linux):
    try:
      result = expandSymlink("/proc/" & $pid & "/exe")
    except OSError:
      discard

  elif defined(macosx):
    proc procPidpath(pid: int32, buffer: pointer, bufferSize: uint32): int32 {.importc: "proc_pidpath", header: "<libproc.h>".}

    var buf: array[4096, char]
    let len = procPidpath(pid.int32, addr buf[0], uint32(buf.len))
    if len > 0:
      result = $cast[cstring](addr buf[0])
  else:
    raise newException(ValueError, "Unsupported platform")


proc initLogger*(self: ServerLogger, levelThreshold: logging.Level, fmtStr: string) =
  self.levelThreshold = levelThreshold
  self.formatter = newFormatter(fmtStr)
  self.hostName = getHostname()
  self.processId = getCurrentProcessId().int32
  self.processName = getProcessNameByPid(self.processId)
  self.tagger.new


proc install*[T: ServerLogger](self: T, name: string) =
  self.name = name
  if self notIn logging.getHandlers():
    logging.addHandler(self)


proc deinstall*[T: ServerLogger](self: T) =
  logging.removeHandler(self)


when useAsync:
  import std/[asyncdispatch]
  method open*(self: ServerLogger, name: string) {.async, base.} = discard
  method close*(self: ServerLogger) {.async, base.} = discard
  method asyncLog*(self: logging.Logger, level: logging.Level, args: varargs[string, `$`]): Future[void] {.base.} = discard
else:
  method open*(self: ServerLogger, name: string) {.base.} = discard
  method close*(self: ServerLogger) {.base.} = discard


#[
proc clone*(src, dest: ServerLogger) =
  dest.levelThreshold = src.levelThreshold
  dest.formatter = src.formatter
  when useThreads:
    dest.threadId = src.threadId
  dest.processId = src.processId
  dest.processName = src.processName
  dest.name = src.name
  dest.hostName = src.hostName
  dest.tagger = src.tagger.clone
]#


proc buildMessage*(self: ServerLogger, level: logging.Level, args: varargs[string, `$`]): string =
  if args.len == 3:
    when useThreads:
      result = self.formatter.build(self.tagger, level, self.name, self.hostName, args[0], args[1], self.processId, self.processName, getThreadId().int32, args[2])
    else:
      result = self.formatter.build(self.tagger, level, self.name, self.hostName, args[0], args[1], self.processId, self.processName, args[2])
  else:
    when useThreads:
      result = self.formatter.build(self.tagger, level, self.name, self.hostName, "", "", self.processId, self.processName, getThreadId().int32, args.join(" "))
    else:
      result = self.formatter.build(self.tagger, level, self.name, self.hostName, "", "", self.processId, self.processName, args.join(" "))


proc tag*(self: ServerLogger, key: string, value: SomeNumber | SomeFloat) =
  self.tagger.tags["\"" & key & "\""] = $value # json key is always a string


proc tag*(self: ServerLogger, key: string, value: string) =
  self.tagger.tags["\"" & key & "\""] = "\"" & value & "\"" # json key is always a string, string value is also a json string


template debug*(logger: ServerLogger, message: string) = log(logger, logging.lvlDebug, message)
template info*(logger: ServerLogger, message: string) = log(logger, logging.lvlInfo, message)
template warn*(logger: ServerLogger, message: string) = log(logger, logging.lvlWarn, message)
template error*(logger: ServerLogger, message: string) = log(logger, logging.lvlError, message)
template fatal*(logger: ServerLogger, message: string) = log(logger, logging.lvlFatal, message)
