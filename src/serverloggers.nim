from logging import nil
export logging.Level
import ./loggers/[consolelogger, rsyslogger, filelogger, serverlogger]

export consolelogger
export rsyslogger
export filelogger
export serverlogger except initLogger, install, deinstall, buildMessage


template log*(lvl: logging.Level, message: string): untyped =
  const (fname, lnum, _) = instantiationInfo()
  logging.log(lvl, fname, lnum, message)


template debug*(message:string) = log(logging.lvlDebug, message)
template info*(message:string) = log(logging.lvlInfo, message)
template warn*(message:string) = log(logging.lvlWarn, message)
template error*(message:string) = log(logging.lvlError, message)
template fatal*(message:string) = log(logging.lvlFatal, message)
