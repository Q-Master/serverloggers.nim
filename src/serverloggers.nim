from logging import nil
export logging.Level
import ./loggers/[consolelogger, rsyslogger, filelogger, serverlogger]
import ./private/util

export consolelogger
export rsyslogger
export filelogger
export serverlogger except initLogger, install, deinstall, buildMessage



when useAsync:
  import std/[asyncdispatch]
  proc logLoop(level: logging.Level, args: varargs[string, `$`]): Future[void] =
    var logs: seq[Future[void]] = @[]
    for logger in logging.getHandlers().items:
      if level >= logger.levelThreshold:
        when compiles asyncLog(logger, level, args):
          logs.add(asyncLog(logger, level, args))
        else:
          log(logger, level, args)
          let f = Future[void]()
          f.complete()
          logs.add(f)
    result = all(logs)

  template log*(level: logging.Level, args: varargs[string, `$`]) =
    ## Logs a message at the specified level to all registered handlers.
    bind logLoop

    if level >= logging.getLogFilter():
      await logLoop(level, args)
else:
  template log*(level: logging.Level, args: varargs[string, `$`]) = logging.log(level, args)


template log*(lvl: logging.Level, message: string): untyped =
  const (fname, lnum, _) = instantiationInfo()
  log(lvl, fname, lnum, message)
  #logging.log(lvl, fname, lnum, message)


template debug*(message:string) = log(logging.lvlDebug, message)
template info*(message:string) = log(logging.lvlInfo, message)
template warn*(message:string) = log(logging.lvlWarn, message)
template error*(message:string) = log(logging.lvlError, message)
template fatal*(message:string) = log(logging.lvlFatal, message)
