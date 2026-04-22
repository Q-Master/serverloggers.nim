import std/[tables]
export tables

type
    LoggerTagger* = ref object
      tags*: Table[string, string]


proc len*(self: LoggerTagger): int =
  result = 2 # {}
  var keys = 0
  for k,v in self.tags.pairs:
    result.inc(k.len+1) # incl :
    result.inc(v.len)
    keys.inc
  if keys > 1:
    result.inc(keys-1) # adding separating commas


proc clone*(self: LoggerTagger): LoggerTagger =
  result.new
  result.tags = self.tags
