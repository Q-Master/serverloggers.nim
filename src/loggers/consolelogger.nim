from logging import nil
import ./[serverlogger]
import ../private/[util]


type
  ConsoleLoggerImpl = ref object of RootObj
    useStderr: bool
    flushThreshold: logging.Level

  ConsoleLogger* = ref object of ServerLogger
    impl: ConsoleLoggerImpl



proc newConsoleLogger*(
  useStderr = true,
  flushThreshold = logging.lvlError,
  levelThreshold = logging.lvlDebug,
  fmtStr = DEFAULT_FORMAT
): ConsoleLogger =
  result.new
  result.impl.new
  result.impl.useStderr = useStderr
  result.impl.flushThreshold = flushThreshold
  result.initLogger(levelThreshold, fmtStr)


method open*(self: ConsoleLogger, name: string) =
  self.install(name)


method close*(self: ConsoleLogger) =
  self.deinstall()


proc clone*(self: ConsoleLogger): ConsoleLogger =
  result.new
  self.clone(result)
  result.impl = self.impl



method log*(logger: ConsoleLogger, level: logging.Level, args: varargs[string, `$`]) {.gcsafe.} =
  if level >= logger.levelThreshold:
    let msg = logger.buildMessage(level, args)
    try:
      var handle = stdout
      if logger.impl.useStderr:
        handle = stderr
      writeLine(handle, msg)
      if level >= logger.impl.flushThreshold: flushFile(handle)
    except IOError:
      discard

