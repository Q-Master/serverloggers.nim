**serverloggers** - is a pure nim loggers collection to use in server scenarios
====

The original loggers which are in the nim system library are limited in formatting and can't be used with syslog/rsyslog,
instead they can be used in js.
This collection of loggers is intended to be used only in compiled code, so no js support is planned yet.

It is now console logger and rsyslog logger included in the collection. It is planned to extend the collection with other loggers.


It is possible to use rsyslog logger in async environments:

```nim
import std/[asyncdispatch]


proc useRsyslog() {.async.} =
  let logger = newRsyslogLogger()
  await logger.open()
  logger.tag("key", "value")
  logger.tag("key1", 8)
  log(lvlDebug, "Test log")
  await logger.close()


waitFor(useRsyslog())
```

also as in sync ones (including threaded):

```nim
proc useRsysLog() =
  var logger = newRsyslogLogger()
  logger.open()
  logger.tag("key", "value")
  logger.tag("key1", 8)
  log(lvlDebug, "Test log")
  logger.close()

useRsysLog()
```

Overview
--------

All loggers register themselves in system logging facilities, so they can be used in complex code without rewriting it.

### Formatting
All loggers support formatting (different from system ones).
Format string is compiled once the logger is created and not parsed every time.  
Format items must be placed to format string as "%(`name`)" where name might be:


| name | desctiption |
|:------:|:-------------:|
| name | the application name |
| levelno | this message logging level |
| levelname | first uppercase letter of this message logging level |
| filename | name of the file which instantiates current log message |
| lineno | line number of the file which instantiates current log message |
| asctime | current message time in "yyyy-MM-dd hh:mm:ss" format |
| msecs | three leading numbers of current message msesc time |
| thread | thread id (might be -1 if unavailable) |
| process| process id (might be -1 if unavailable) |
| tags | simple json-like key-value dictionary supporting only strings, floats, ints in values |
| message | the message itself|

Default format string is: "%(asctime).%(msecs) %(process) %(levelname) %(filename):%(lineno)] %(name) %(tags) %(message)"


### Console logger

Console logger simply dumps log messages to stdout or stderr. It might be created using

```nim
proc newConsoleLogger*(
  useStderr = false,
  flushThreshold = logging.lvlError,
  levelThreshold = logging.lvlDebug,
  fmtStr = DEFAULT_FORMAT
)
```

params:

| name | description |
|:----:|:-----------:|
| useStderr | if `true` the log output will be to stderr instead of stdout |
| flushThreshold | the log level which forces logger to flush buffers immediately |
| levelThreshold | the minimum level to output |
| fmtStr | the format string (see [formatting](#Formatting)) |


### Rsyslog logger

Rsyslog logger splits to async and threaded ones. When compiling async project `--d:useAsync` must present in build params.
It might be created using:

```nim
proc newRsyslogLogger*(
  url = DEFAULT_URL,
  facility: RsyslogFacilities = FAC_USER,
  levelThreshold = logging.lvlDebug,
  fmtStr = DEFAULT_FORMAT
)
```

params:

| name | description |
|:----:|:-----------:|
| url | standard url with schema (see [schemas](#possible-schemas))|
| facility | the log facility FAC_USER is the best choice|
| levelThreshold | the minimum level to output |
| fmtStr | the format string (see [formatting](#Formatting)) |


#### Possible schemas

Rsyslog logger supports limited amount of connection schemas:

- "unix" for udp unix sockets with path to unix socket e.x. "unix:///dev/log"
- "unix_tcp" for tcp unix sockets with path to unix socket e.x. "unix_tcp:///dev/log"
- "tcp" for tcp connection e.x. "tcp://localhost:514"
- "udp" for udp connection e.x. "udp://localhost:514"
