# MetaCoffee Bootstrapping

This is the list of OMeta definitions for bootstrapping the **MetaCoffee**

## OMetaJS whitespace significant in original OMetaJS syntax

### DentParser

Uses spaces to indent lines.

- **nl** saves the start position of each line on `\n` match
- **dent** matches a new line and returns its indentation in number of spaces
- **nodent** matches only if next line has the same indentation as given
- **moredent** matches if next line has bigger indentation and returns a new line
  followed by the additional indentation
- **lessdent** matches if next line has same or smaller indentation or it is the
  end of input
- **setdent** sets the level of indentation treated as a space
- **redent** set the level of indentation treated as a space to a previous level
- **spacedent** to be included in `space` rule, matches indent of a level set by
  setdent

Overwrites base-rule **exactly** to use **nl** instead of matching \n and
removes \n from super-rule **space**.

    ometa DentParser {
      initialize     = {this.mindent = new Stack().push(-1)},
      exactly        = '\n' apply("nl")
                     | :other ^exactly(other),
      inspace        = ~exactly('\n') space,
      nl             = ^exactly('\n') pos:p {this.lineStart = p} -> '\n',
      blankLine      = inspace* '\n',
      dent           = inspace* '\n' blankLine* ' '*:ss -> ss.length,
      linePos        = pos:p -> (p - (this.lineStart || 0)),
      stripdent :d :p -> ('\n' + $.repeat(d - p, ' ')),
      nodent :p      = dent:d ?(d == p),
      moredent :p    = dent:d ?(d >= p) stripdent(d, p),
      lessdent :p    = dent:d ?(d <= p)
                     | inspace* end,
      setdent :p     = {this.mindent.push(p)},
      redent         = {this.mindent.pop()},
      spacedent      = ?(this.mindent.top() >= 0) moredent(this.mindent.top())
    }

### SemActionParser

Fake semantic parser, given indentation level or delimiting requirement matches
JavaScript and returns it.
Also strips additional indentation below the given level.

- **delimSemAction** matches JavaScript inside curly braces
- **semAction** matches either JavaScript with indent bigger than p or
  **delimSemAction**

Strings cannot contain escaped quotes at the moment.

    ometa JSSemActionParser <: BSJSParser {
      semAction = expr:e spaces end -> e
                  | (srcElem:s &srcElem -> s)*:ss
                    (expr:r sc? -> [#return, r] | srcElem):s  {ss.push(s)}
                    spaces end
                             -> [#send, #call,
                                        [#func, [], [#begin].concat(ss)],
                                        [#this]]
    }

    ometa SemActionParser <: DentParser {
      initialize     = {this.dentlevel = 0} ^initialize,
      between :s :e  = seq(s) text(true):t seq(e) -> t,
      pairOf :s :e   = between(s, e):t -> (s + t + e),
      delims         = '{' | '(' | '['
                     | '}' | ')' | ']',
      pair           = pairOf('{', '}')
                     | pairOf('(', ')')
                     | pairOf('[', ']'),
      text3          = dent:d stripdent(d, this.dentlevel)
                     | ~exactly('\n') anything,
      text2 :inside  = fromTo('/*', '*/')
                     | fromTo('"', '"')
                     | fromTo('\'', '\'')
                     | ?inside ~delims text3
                     | ~exactly('\n') ~delims anything
                     | pair,
      text :inside   = text2(inside)*:ts          -> ts.join(''),
      line           = text(false),
      nextLine :p    = moredent(p):d line:l       -> (d + l),
      exp :p         = line:fl nextLine(p)*:ls    -> (fl + ls.join('')),
      delimSemAction = spaces between('{', '}'):e -> JSSemActionParser.matchAll(e, "semAction"),
      semAction :p   = {this.dentlevel = p}
                       (delimSemAction
                       | exp(p):e -> JSSemActionParser.matchAll(e, "semAction"))
    }

### OMetaParser

Matches MetaCoffee whitespace-significant syntax instead of original OMeta
syntax.

Notable changes to the original syntax:

- semantic predicates and actions must be either delimited or follow the
  arrow operator
- negative lookahead is prefixed with `!` instead of `~`
- semantic predicates are prefixed with `&`, analogous to lookahead
- there is a new inverse semantic predicate, prefixed with `!` (akin to
  negative lookahead)
- keyword `<:` is now `extends` mimicking CoffeeScript classes
- syntax of OMeta is whitespace-significant, most noticebly there is no need
  for a comma at the end of a rule

Some of these (f.e. semantic predicates syntax) were inspired by PEG.js.

Indentation rules:

- header must be followed by an indented list of rules (or ML-style rule parts),
  all rules must be be indented the same number of spaces
- rule's parameters must either follow on the same line or be indented more
  than the rule's name
- same applies to the optional equal sign
- rule right-hand side must either follow `=` on the same line or be indented
  at least as much as the equal sign
- tokens inside parentheses do not need to be indented
- semantic actions after `->` must follow on the same line or be indented on the
  next lines to start right **after** the arrow sign, the whitespace equal to
  additional indentation is stripped from the semantic action

.

    ometa OMetaParser <: DentParser {
      lineComment    = fromTo('# ', '\n'),
      blockComment   = fromTo('#>', '<#'),
      space          = ' ' | spacedent | lineComment | blockComment,
      blankLine      = ' '* (lineComment | blockComment ' '* '\n')
                     | ^blankLine,
      nameFirst      = '_' | '$' | letter,
      bareName       = <nameFirst (nameFirst | digit)*>,
      name           = spaces bareName,
      hexValue :ch                                                         -> '0123456709abcdef'.indexOf(ch.toLowerCase()),
      hexDigit       = char:x hexValue(x):v ?(v >= 0)                      -> v,
      escapedChar    = <'\\' ( 'u' hexDigit hexDigit hexDigit hexDigit
                             | 'x' hexDigit hexDigit
                             | char                                   )>:s -> unescape(s)
                     | char,
      charSequence   = '"'  ( ~'"' escapedChar)*:xs  '"'                   -> [#App, #token,   programString(xs.join(''))],
      string         = '\'' (~'\'' escapedChar)*:xs '\''                   -> [#App, #exactly, programString(xs.join(''))],
      number         = <'-'? digit+>:n                                     -> [#App, #exactly, n],
      keyword :xs    = token(xs) ~letterOrDigit                            -> xs,
      args           = '(' listOf(#hostExpr, ','):xs ")"                   -> xs
                     | empty                                               -> [],
      application    = "^"          name:rule args:as                      -> [#App, "super",        "'" + rule + "'"].concat(as)
                     | name:grm "." name:rule args:as                      -> [#App, "foreign", grm, "'" + rule + "'"].concat(as)
                     |              name:rule args:as                      -> [#App, rule].concat(as),
      hostExpr        = BSSemActionParser.expr:r                              BSJSTranslator.trans(r),
      closedHostExpr  = SemActionParser.delimSemAction:r                      BSJSTranslator.trans(r),
      openHostExpr :p = SemActionParser.semAction(p):r                        BSJSTranslator.trans(r),
      semAction      = closedHostExpr:x                                    -> [#Act, x],
      arrSemAction   = "->" linePos:p openHostExpr(p):x                    -> [#Act, x],
      semPred        = "&" closedHostExpr:x                                -> [#Pred, x]
                     | "!" closedHostExpr:x                                -> [#Not, [#Pred, x]],
      expr :p        = setdent(p) expr5:x {this.redent()}                  -> x,
      expr5          = expr4(true):x ( "|" expr4(true))+:xs                -> [#Or,  x].concat(xs)
                     | expr4(true):x ("||" expr4(true))+:xs                -> [#XOr, x].concat(xs)
                     | expr4(false),
      expr4 :ne      =                expr3*:xs arrSemAction:act           -> [#And].concat(xs).concat([act])
                     | ?ne            expr3+:xs                            -> [#And].concat(xs)
                     | ?(ne == false) expr3*:xs                            -> [#And].concat(xs),
      optIter :x     = '*'                                                 -> [#Many,  x]
                     | '+'                                                 -> [#Many1, x]
                     | '?'                                                 -> [#Opt,   x]
                     | empty                                               -> x,
      optBind :x     = ':' name:n                                          -> { this.locals[n] = true; [#Set, n, x] }
                     | empty                                               -> x,
      expr3          = ":" name:n                                          -> { this.locals[n] = true; [#Set, n, [#App, #anything]] }
                     | (expr2:x optIter(x) | semAction):e optBind(e)
                     | semPred,
      expr2          = "!" expr2:x                                         -> [#Not,       x]
                     | "&" expr1:x                                         -> [#Lookahead, x]
                     | expr1,
      expr1          = application
                     | ( keyword('undefined') | keyword('nil')
                       | keyword('true')      | keyword('false') ):x       -> [#App, #exactly, x]
                     | spaces (charSequence | string | number)
                     | "["  expr(0):x "]"                                  -> [#Form,      x]
                     | "<"  expr(0):x ">"                                  -> [#ConsBy,    x]
                     | "@<" expr(0):x ">"                                  -> [#IdxConsBy, x]
                     | "("  expr(0):x ")"                                  -> x,
      ruleName       = bareName,
      rule           = &(ruleName:n) !(this.locals = {})
                       linePos:p setdent(p + 1) rulePart(n):x
                       (nodent(p) rulePart(n))*:xs {this.redent()}         -> [#Rule, n, propertyNames(this.locals),
                                                                               [#Or, x].concat(xs)],
      rulePart :rn   = ruleName:n ?(n == rn) expr4(false):b1
                       ( spaces linePos:p '=' expr(p):b2            -> [#And, b1, b2]
                       | empty                                -> b1
                       ),
      grammar        = (inspace*:ss -> ss.length):ip
                       keyword('ometa') name:n
                       ( keyword('extends') name | empty -> 'OMeta' ):sn
                       moredent(ip)
                         linePos:p rule:r
                         (nodent(p) rule)*:rs
                       lessdent(ip)                                         BSOMetaOptimizer.optimizeGrammar(
                                                                                [#Grammar, n, sn, r].concat(rs)
                                                                              )
    }


## OMetaJS whitespace significant in its own syntax

### DentParser

    ometa DentParser
      initialize     = {this.mindent = new Stack().push(-1)}
      exactly        = '\n' apply("nl")
                     | :other ^exactly(other)
      inspace        = !exactly('\n') space
      nl             = ^exactly('\n') pos:p {this.lineStart = p} -> '\n'
      blankLine      = inspace* '\n'
      dent           = inspace* '\n' blankLine* ' '*:ss -> ss.length
      linePos        = pos:p -> (p - (this.lineStart || 0))
      stripdent :d :p -> ('\n' + $.repeat(d - p, ' '))
      nodent :p      = dent:d &{d == p}
      moredent :p    = dent:d &{d >= p} stripdent(d, p)
      lessdent :p    = dent:d &{d <= p}
                     | inspace* end
      setdent :p     = {this.mindent.push(p)}
      redent         = {this.mindent.pop()}
      spacedent      = &{this.mindent.top() >= 0} moredent(this.mindent.top())

### SemActionParser

    ometa JSSemActionParser extends BSJSParser
      semAction = expr:e spaces end -> e
                | (srcElem:s &srcElem -> s)*:ss
                  (expr:r sc? -> ['return', r]
                  | srcElem):s  {ss.push(s)}
                  spaces end
                             -> ['send', 'call',
                                        ['func', [], ['begin'].concat(ss)],
                                        ['this']]

    ometa SemActionParser extends DentParser
      initialize     = {this.dentlevel = 0} ^initialize
      between :s :e  = seq(s) text(true):t seq(e) -> t
      pairOf :s :e   = between(s, e):t -> s + t + e
      delims         = '{' | '(' | '['
                     | '}' | ')' | ']'
      pair           = pairOf('{', '}')
                     | pairOf('(', ')')
                     | pairOf('[', ']')
      text3          = dent:d stripdent(d, this.dentlevel)
                     | !exactly('\n') anything
      text2 :inside  = fromTo('/*', '*/')
                     | fromTo('"', '"')
                     | fromTo('\'', '\'')
                     | &{inside} !delims text3
                     | !exactly('\n') !delims anything
                     | pair
      text :inside   = text2(inside)*:ts          -> ts.join('')
      line           = text(false)
      nextLine :p    = moredent(p):d line:l       -> d + l
      exp :p         = line:fl nextLine(p)*:ls    -> fl + ls.join('')
      delimSemAction = spaces between('{', '}'):e -> JSSemActionParser.matchAll(e, "semAction")
      semAction :p   = {this.dentlevel = p}
                       (delimSemAction
                       | exp(p):e -> JSSemActionParser.matchAll(e, "semAction"))

### OMetaParser

    ometa OMetaParser extends DentParser
      lineComment    = fromTo('# ', '\n')
      blockComment   = fromTo('#>', '<#')
      space          = ' ' | spacedent | lineComment | blockComment
      blankLine      = ' '* (lineComment | blockComment ' '* '\n')
                     | ^blankLine
      nameFirst      = '_' | '$' | letter
      bareName       = <nameFirst (nameFirst | digit)*>
      name           = spaces bareName
      hexValue :ch                                                         -> '0123456709abcdef'.indexOf(ch.toLowerCase())
      hexDigit       = char:x {this.hexValue(x)}:v &{v >= 0}               -> v
      escapedChar    = <'\\' ( 'u' hexDigit hexDigit hexDigit hexDigit
                             | 'x' hexDigit hexDigit
                             | char                                   )>:s -> unescape(s)
                     | char
      charSequence   = '"'  ( !'"' escapedChar)*:xs  '"'                   -> ['App', 'token',   programString(xs.join(''))]
      string         = '\'' (!'\'' escapedChar)*:xs '\''                   -> ['App', 'exactly', programString(xs.join(''))]
      number         = <'-'? digit+>:n                                     -> ['App', 'exactly', n]
      keyword :xs    = token(xs) !letterOrDigit                            -> xs
      args           = '(' listOf('hostExpr', ','):xs ")"                  -> xs
                     | empty                                               -> []
      application    = "^"          name:rule args:as                      -> ['App', "super",        "'" + rule + "'"].concat(as)
                     | name:grm "." name:rule args:as                      -> ['App', "foreign", grm, "'" + rule + "'"].concat(as)
                     |              name:rule args:as                      -> ['App', rule].concat(as)
      hostExpr        = BSSemActionParser.expr:r                              BSJSTranslator.trans(r)
      closedHostExpr  = SemActionParser.delimSemAction:r                      BSJSTranslator.trans(r)
      openHostExpr :p = SemActionParser.semAction(p):r                        BSJSTranslator.trans(r)
      semAction      = closedHostExpr:x                                    -> ['Act', x]
      arrSemAction   = "->" linePos:p openHostExpr(p):x                    -> ['Act', x]
      semPred        = "&" closedHostExpr:x                                -> ['Pred', x]
                     | "!" closedHostExpr:x                                -> ['Not', ['Pred', x]]
      expr :p        = setdent(p) expr5:x {this.redent()}                  -> x
      expr5          = expr4(true):x ("|" expr4(true))+:xs                 -> ['Or',  x].concat(xs)
                     | expr4(true):x ("||" expr4(true))+:xs                -> ['XOr', x].concat(xs)
                     | expr4(false)
      expr4 :ne      =       expr3*:xs arrSemAction:act                    -> ['And'].concat(xs).concat([act])
                     | &{ne} expr3+:xs                                     -> ['And'].concat(xs)
                     | !{ne} expr3*:xs                                     -> ['And'].concat(xs)
      optIter :x     = '*'                                                 -> ['Many',  x]
                     | '+'                                                 -> ['Many1', x]
                     | '?'                                                 -> ['Opt',   x]
                     | empty                                               -> x
      optBind :x     = ':' name:n                                          -> this.locals.add(n); ['Set', n, x]
                     | empty                                               -> x
      expr3          = ":" name:n                                          -> this.locals.add(n); ['Set', n, ['App', 'anything']]
                     | (expr2:x optIter(x) | semAction):e optBind(e)
                     | semPred
      expr2          = "!" expr2:x                                         -> ['Not',       x]
                     | "&" expr1:x                                         -> ['Lookahead', x]
                     | expr1
      expr1          = application
                     | ( keyword('undefined') | keyword('nil')
                       | keyword('true')      | keyword('false') ):x       -> ['App', 'exactly', x]
                     | spaces (charSequence | string | number)
                     | "["  expr(0):x "]"                                  -> ['Form',      x]
                     | "<"  expr(0):x ">"                                  -> ['ConsBy',    x]
                     | "@<" expr(0):x ">"                                  -> ['IdxConsBy', x]
                     | "("  expr(0):x ")"                                  -> x
      ruleName       = bareName
      rule           = &(ruleName:n) {this.locals = new Set()}
                        linePos:p setdent(p + 1) rulePart(n):x
                         (nodent(p) rulePart(n))*:xs {this.redent()}       -> ['Rule', n, this.locals.values(),
                                                                               ['Or', x].concat(xs)]
      rulePart :rn   = ruleName:n &{n == rn} expr4(false):b1
                       ( spaces linePos:p '=' expr(p):b2 -> ['And', b1, b2]
                       | empty                           -> b1
                       )
      grammar        = linePos:ip
                       keyword('ometa') name:n
                       ( keyword('extends') name | empty -> 'OMeta' ):sn
                       moredent(ip)
                         linePos:p rule:r
                         (nodent(p) rule)*:rs
                       lessdent(ip)                                         BSOMetaOptimizer.optimizeGrammar(
                                                                                ['Grammar', n, sn, r].concat(rs)
                                                                              )

## MetaCoffee in OMetaJS whitespace significant

### SemActionParser

    ometa CSParser
      action :input :args    = compile(input, args):compiled (simplify(compiled) | -> compiled)
      simpleExp :input :args = compile(input, args):compiled simplify(compiled)
      compile :input :args  -> $.trim(BSCoffeeScriptCompiler.compile("((" + args.join() + ") ->\n  "
                                                 + input.replace(/\n/g, '\n  ') + ").call(this)", {bare:true})).replace(/^\(function.*?\)/, '(function()').replace(/;$/, '');
      simplify :compiled ->  var lines = compiled.split('\n');
                             if (lines.length < 2 || !lines[1].match(/^ +return/)) {
                               throw this.fail;
                             }
                             exp = lines.slice(1, -1);
                             exp[0] = exp[0].replace(/^ +return /, '');
                             exp.join('\n').replace(/;$/, '');

    ometa SemActionParser extends BSDentParser
      initialize     = {this.dentlevel = 0} ^initialize
      between :s :e  = seq(s) text(true):t seq(e) -> t
      pairOf :s :e   = between(s, e):t -> s + t + e
      delims         = '{' | '(' | '['
                     | '}' | ')' | ']'
      pair           = pairOf('{', '}')
                     | pairOf('(', ')')
                     | pairOf('[', ']')
      text3          = dent:d stripdent(d, this.dentlevel)
                     | !exactly('\n') anything
      fromTo :s :e   = <seq(s) (seq('\\\\') | seq('\\') seq(e) | !seq(e) char)* seq(e)>
      text2 :inside  = fromTo('###', '###')
                     | fromTo('"', '"')
                     | fromTo('\'', '\'')
                     | &{inside} !delims text3
                     | !exactly('\n') !delims anything
                     | pair
      text :inside   = text2(inside)*:ts          -> ts.join('')
      line           = text(false)
      nextLine :p    = moredent(p):d line:l       -> d + l
      exp :p         = line:fl nextLine(p)*:ls    -> fl + ls.join('')
      simpleExp :args      = spaces (!delims !',' anything | pair)+:ts CSParser.simpleExp(ts.join(''), args)
      delimSemAction :args = spaces between('{', '}'):e CSParser.action(e, args)
      semAction :p :args   = {this.dentlevel = p}
                           (delimSemAction
                           | exp(p):e CSParser.action(e, args))

### OMetaParser

    ometa OMetaParser extends BSDentParser
      lineComment    = fromTo('# ', '\n')
      blockComment   = fromTo('#>', '<#')
      space          = ' ' | spacedent | lineComment | blockComment
      blankLine      = ' '* (lineComment | blockComment ' '* '\n')
                     | ^blankLine
      nameFirst      = '_' | '$' | letter
      bareName       = <nameFirst (nameFirst | digit)*>
      name           = spaces bareName
      hexValue :ch                                                         -> '0123456709abcdef'.indexOf(ch.toLowerCase())
      hexDigit       = char:x {this.hexValue(x)}:v &{v >= 0}               -> v
      escapedChar    = <'\\' ( 'u' hexDigit hexDigit hexDigit hexDigit
                             | 'x' hexDigit hexDigit
                             | char                                   )>:s -> unescape(s)
                     | char
      charSequence   = '"'  ( !'"' escapedChar)*:xs  '"'                   -> ['App', 'token',   programString(xs.join(''))]
      string         = '\'' (!'\'' escapedChar)*:xs '\''                   -> ['App', 'exactly', programString(xs.join(''))]
      number         = <'-'? digit+>:n                                     -> ['App', 'exactly', n]
      keyword :xs    = token(xs) !letterOrDigit                            -> xs
      args           = '(' listOf('hostExpr', ','):xs ")"                  -> xs
                     | empty                                               -> []
      application    = "^"          name:rule args:as                      -> ['App', "super",        "'" + rule + "'"].concat(as)
                     | name:grm "." name:rule args:as                      -> ['App', "foreign", grm, "'" + rule + "'"].concat(as)
                     |              name:rule args:as                      -> ['App', rule].concat(as)
      hostExpr        = SemActionParser.simpleExp(this.locals.values()):r
      closedHostExpr  = SemActionParser.delimSemAction(this.locals.values()):r
      openHostExpr :p = SemActionParser.semAction(p, this.locals.values()):r
      semAction      = closedHostExpr:x                                    -> ['Act', x]
      arrSemAction   = "->" linePos:p openHostExpr(p):x                    -> ['Act', x]
      semPred        = "&" closedHostExpr:x                                -> ['Pred', x]
                     | "!" closedHostExpr:x                                -> ['Not', ['Pred', x]]
      expr :p        = setdent(p) expr5:x {this.redent()}                  -> x
      expr5          = expr4(true):x ("|" expr4(true))+:xs                 -> ['Or',  x].concat(xs)
                     | expr4(true):x ("||" expr4(true))+:xs                -> ['XOr', x].concat(xs)
                     | expr4(false)
      expr4 :ne      =       expr3*:xs arrSemAction:act                    -> ['And'].concat(xs).concat([act])
                     | &{ne} expr3+:xs                                     -> ['And'].concat(xs)
                     | !{ne} expr3*:xs                                     -> ['And'].concat(xs)
      optIter :x     = '*'                                                 -> ['Many',  x]
                     | '+'                                                 -> ['Many1', x]
                     | '?'                                                 -> ['Opt',   x]
                     | empty                                               -> x
      optBind :x     = ':' name:n                                          -> this.locals.add(n); ['Set', n, x]
                     | empty                                               -> x
      expr3          = ":" name:n                                          -> this.locals.add(n); ['Set', n, ['App', 'anything']]
                     | (expr2:x optIter(x) | semAction):e optBind(e)
                     | semPred
      expr2          = "!" expr2:x                                         -> ['Not',       x]
                     | "&" expr1:x                                         -> ['Lookahead', x]
                     | expr1
      expr1          = application
                     | ( keyword('undefined') | keyword('nil')
                       | keyword('true')      | keyword('false') ):x       -> ['App', 'exactly', x]
                     | spaces (charSequence | string | number)
                     | "["  expr(0):x "]"                                  -> ['Form',      x]
                     | "<"  expr(0):x ">"                                  -> ['ConsBy',    x]
                     | "@<" expr(0):x ">"                                  -> ['IdxConsBy', x]
                     | "("  expr(0):x ")"                                  -> x
      ruleName       = bareName
      rule           = &(ruleName:n) {this.locals = new Set()}
                        linePos:p setdent(p + 1) rulePart(n):x
                         (nodent(p) rulePart(n))*:xs {this.redent()}       -> ['Rule', n, this.locals.values(),
                                                                               ['Or', x].concat(xs)]
      rulePart :rn   = ruleName:n &{n == rn} expr4(false):b1
                       ( spaces linePos:p '=' expr(p):b2 -> ['And', b1, b2]
                       | empty                           -> b1
                       )
      grammar        = (inspace*:ss -> ss.length):ip
                       keyword('ometa') name:n
                       ( keyword('extends') name | empty -> 'OMeta' ):sn
                       moredent(ip)
                         linePos:p rule:r
                         (nodent(p) rule)*:rs
                       lessdent(ip)                                         BSOMetaOptimizer.optimizeGrammar(
                                                                                ['Grammar', n, sn, r].concat(rs)
                                                                              )

## MetaCoffee in MetaCoffee

### SemActionParser

    ometa CSParser
      action :input :args    = compile(input, args):compiled (simplify(compiled) | -> compiled)
      simpleExp :input :args = compile(input, args):compiled simplify(compiled)
      compile :input :args  -> $.trim(BSCoffeeScriptCompiler.compile("((" + args.join() + ") ->\n  " +
                                           input.replace(/\n/g, '\n  ') + ").call(this)", {bare:true})).replace(/^\s*(var[^]*?)?(\(function[^]*?\{)([^]*)/, "(function(){$1$3").replace /;$/, ''
      simplify :compiled ->  lines = compiled.split('\n')
                             if lines.length < 2 || !lines[1].match(/^ +return/)
                               throw @fail
                             exp = lines[1...-1]
                             exp[0] = exp[0].replace /^ +return /, ''
                             exp.join('\n').replace /;$/, ''

    ometa SemActionParser extends BSDentParser
      initialize     = {@dentlevel = 0; @sep = 'none'} ^initialize
      none           = !empty
      comma          = ','
      between :s :e  = seq(s) text(true):t seq(e) -> t
      pairOf :s :e   = between(s, e):t -> s + t + e
      delims         = '{' | '(' | '['
                     | '}' | ')' | ']'
      pair           = pairOf('{', '}')
                     | pairOf('(', ')')
                     | pairOf('[', ']')
      text3          = dent:d stripdent(d, @dentlevel)
                     | !exactly('\n') anything
      fromTo :s :e   = <seq(s) (seq('\\\\') | seq('\\') seq(e) | !seq(e) char)* seq(e)>
      text2 :inside  = fromTo('###', '###')
                     | fromTo('"', '"')
                     | fromTo('\'', '\'')
                     | <'/' (seq('\\\\') | seq('\\') '/' | !exactly('\n') !'/' char)+ '/'>
                     | &{inside} !delims text3
                     | !exactly('\n') !delims !apply(@sep) anything
                     | pair
      text :inside   = text2(inside)*:ts          -> ts.join ''
      line           = text(false)
      nextLine :p    = moredent(p):d line:l       -> d + l
      exp :p         = line:fl nextLine(p)*:ls    -> fl + ls.join ''
      simpleExp :args      = spaces {@sep = 'comma'} text(false):t CSParser.simpleExp(t, args)
      delimSemAction :args = spaces between('{', '}'):e CSParser.action(e, args)
      semAction :p :args   = {@dentlevel = p}
                             (delimSemAction
                             | exp(p):e CSParser.action(e, args))

### OMetaParser

    ometa OMetaParser extends BSDentParser
      lineComment    = fromTo('# ', '\n')
      blockComment   = fromTo('#>', '<#')
      space          = ' ' | spacedent | lineComment | blockComment
      blankLine      = ' '* (lineComment | blockComment ' '* '\n')
                     | ^blankLine
      nameFirst      = '_' | '$' | letter
      bareName       = <nameFirst (nameFirst | digit)*>
      name           = spaces bareName
      hexDigit       = char:x {this.hexValue(x)}:v &{v >= 0}               -> v
      escapedChar    = <'\\' ( 'u' hexDigit hexDigit hexDigit hexDigit
                             | 'x' hexDigit hexDigit
                             | char                                   )>:s -> unescape s
                     | char
      charSequence   = '"'  ( !'"' escapedChar)*:xs  '"'                   -> ['App', 'token',   programString xs.join '']
      string         = '\'' (!'\'' escapedChar)*:xs '\''                   -> ['App', 'exactly', programString xs.join '']
      number         = <'-'? digit+>:n                                     -> ['App', 'exactly', n]
      keyword :xs    = token(xs) !letterOrDigit                            -> xs
      args           = '(' listOf('hostExpr', ','):xs ")"                  -> xs
                     | empty                                               -> []
      application    = "^"          name:rule args:as                      -> ['App', "super",        "'" + rule + "'"].concat as
                     | name:grm "." name:rule args:as                      -> ['App', "foreign", grm, "'" + rule + "'"].concat as
                     |              name:rule args:as                      -> ['App', rule].concat as
      hostExpr        = SemActionParser.simpleExp(@locals.values()):r
      closedHostExpr  = SemActionParser.delimSemAction(@locals.values()):r
      openHostExpr :p = SemActionParser.semAction(p, @locals.values()):r
      semAction      = closedHostExpr:x                                    -> ['Act', x]
      arrSemAction   = "->" linePos:p openHostExpr(p):x                    -> ['Act', x]
      semPred        = "&" closedHostExpr:x                                -> ['Pred', x]
                     | "!" closedHostExpr:x                                -> ['Not', ['Pred', x]]
      expr :p        = setdent(p) expr5:x {this.redent()}                  -> x
      expr5          = expr4(true):x ("|" expr4(true))+:xs                 -> ['Or',  x].concat xs
                     | expr4(true):x ("||" expr4(true))+:xs                -> ['XOr', x].concat xs
                     | expr4(false)
      expr4 :ne      =       expr3*:xs arrSemAction:act                    -> ['And'].concat(xs).concat [act]
                     | &{ne} expr3+:xs                                     -> ['And'].concat xs
                     | !{ne} expr3*:xs                                     -> ['And'].concat xs
      optIter :x     = '*'                                                 -> ['Many',  x]
                     | '+'                                                 -> ['Many1', x]
                     | '?'                                                 -> ['Opt',   x]
                     | empty                                               -> x
      optBind :x     = ':' name:n                                          -> @locals.add n; ['Set', n, x]
                     | empty                                               -> x
      expr3          = ":" name:n                                          -> @locals.add n; ['Set', n, ['App', 'anything']]
                     | (expr2:x optIter(x) | semAction):e optBind(e)
                     | semPred
      expr2          = "!" expr2:x                                         -> ['Not',       x]
                     | "&" expr1:x                                         -> ['Lookahead', x]
                     | expr1
      expr1          = application
                     | ( keyword('undefined') | keyword('nil')
                       | keyword('true')      | keyword('false') ):x       -> ['App', 'exactly', x]
                     | spaces (charSequence | string | number)
                     | "["  expr(0):x "]"                                  -> ['Form',      x]
                     | "<"  expr(0):x ">"                                  -> ['ConsBy',    x]
                     | "@<" expr(0):x ">"                                  -> ['IdxConsBy', x]
                     | "("  expr(0):x ")"                                  -> x
      ruleName       = bareName
      rule           = &(ruleName:n) {@locals = new Set}
                        linePos:p setdent(p + 1) rulePart(n):x
                         (nodent(p) rulePart(n))*:xs {this.redent()}       -> ['Rule', n, this.locals.values(),
                                                                               ['Or', x].concat xs]
      rulePart :rn   = ruleName:n &{n == rn} expr4(false):b1
                       ( spaces linePos:p '=' expr(p):b2 -> ['And', b1, b2]
                       | empty                           -> b1
                       )
      grammar        = (inspace*:ss -> ss.length):ip
                       keyword('ometa') name:n
                       ( keyword('extends') name | empty -> 'OMeta' ):sn  {log ip}
                       moredent(ip)
                         linePos:p rule:r
                         (nodent(p) rule)*:rs
                       lessdent(ip)                                         BSOMetaOptimizer.optimizeGrammar(
                                                                                ['Grammar', n, sn, r].concat rs
                                                                            )

### MetaCoffeeParser

ometa MetaCoffeeParser extends BSDentParser
  ometa :first  = (&{first} | '\n') inspace*:ss prepend(ss)
                  OMetaParser2.grammar:g                    -> ['OMeta', ss.join(''), g]
  coffee      = anything:x (!ometa(no) anything)*:xs        -> ['CoffeeScript', x + xs.join '']
  topLevel    = (blankLine* ometa(yes) | coffee):x 
                           (ometa(no)  | coffee)*:xs        -> [x].concat xs
              | end                                         -> [['CoffeeScript', '']]

ometa MetaCoffeeTranslator
  trans = ([:t apply(t):ans] -> ans)*:xs {log xs.join('')}-> BSCoffeeScriptCompiler.compile xs.join(''), bare:true
  CoffeeScript :t
  OMeta      :ss :t BSOMetaTranslator.trans(t):js -> '\n' + ss + '`' + js + '`\n'