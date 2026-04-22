from logging import nil
import ./[serverlogger]
import ../private/[util]

when useAsync:
  import std/[asyncdispatch, asyncfile]

type
  ConsoleLoggerImpl = ref object of RootObj
    when useAsync:
      fd: AsyncFile
    else:
      fd: File
    useStderr: bool
    flushThreshold: logging.Level

  ConsoleLogger* = ref object of ServerLogger
    impl: ConsoleLoggerImpl



proc newConsoleLogger*(
  useStderr = true,
  levelThreshold = logging.lvlDebug,
  fmtStr = DEFAULT_FORMAT
): ConsoleLogger =
  result.new
  result.impl.new
  result.impl.useStderr = useStderr
  result.initLogger(levelThreshold, fmtStr)


when useAsync:
  method open*(self: ConsoleLogger, name: string) {.async.} =
    self.impl.fd = newAsyncFile((if self.impl.useStderr: stderr else: stdout).getFileHandle().AsyncFD)
    self.install(name)

  method close*(self: ConsoleLogger) {.async.}=
    self.deinstall()

  method asyncLog*(logger: ConsoleLogger, level: logging.Level, args: varargs[string, `$`]): Future[void] =
    if level >= logger.levelThreshold:
      proc realWrite(msg: string) {.async.} =
        try:
          await logger.impl.fd.write(msg)
        except:
          discard
      let msg = logger.buildMessage(level, args) & "\n"
      result = realWrite(msg)
    else:
      result = Future[void]()
      result.complete()

  method log*(logger: ConsoleLogger, level: logging.Level, args: varargs[string, `$`]) =
    waitFor(asyncLog(logger, level, args))

else:
  method open*(self: ConsoleLogger, name: string) =
    self.impl.fd = (if self.impl.useStderr: stderr else: stdout)
    self.install(name)

  method close*(self: ConsoleLogger) =
    self.deinstall()

  method log*(logger: ConsoleLogger, level: logging.Level, args: varargs[string, `$`]) =
    if level >= logger.levelThreshold:
      let msg = logger.buildMessage(level, args)
      try:
        writeLine(logger.impl.fd, msg)
      except IOError:
        discard

#[
proc clone*(self: ConsoleLogger): ConsoleLogger =
  result.new
  self.clone(result)
  result.impl = self.impl
]#
