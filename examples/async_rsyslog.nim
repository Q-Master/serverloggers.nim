import serverloggers
import std/[asyncdispatch]


proc useRsyslog() {.async.} =
  let logger: ServerLogger = newRsyslogLogger()
  logger.open("AsyncRsysLogTest")
  logger.tag("key", "value")
  logger.tag("key1", 8)
  log(lvlDebug, "Test log")
  logger.close()


proc useFileLog() {.async.}=
  var logger = newFileLogger("test.log")
  logger.open("AsyncFileLogTest")
  logger.tag("key", "value")
  logger.tag("key1", 8)
  log(lvlDebug, "Test log")
  logger.close()

waitFor(useRsyslog())
waitFor(useFileLog())
