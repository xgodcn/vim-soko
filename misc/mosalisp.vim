" mosalisp.vim - lisp interpreter
" Maintainer:   Yukihiro Nakadaira <yukihiro.nakadaira@gmail.com>
" License:      This file is placed in the public domain.
" Last Change:  2007-08-18
"
" Usage:
"   :source mosalisp.vim
"   :call mosalisp.repl()   " type (exit) or CTRL-C to exit
"
" Example:
"   :call mosalisp.repl()
"   > (define func (lambda () (display "hello, world")(newline)))
"   > (func)
"   hello, world
"   > (:call "append" 0 '("line1" "line2"))
"   => 0
"   > (:execute "new file.txt")
"   "file.txt" [New File]
"   > (let loop ((i 0))
"   >> (when (< i 3)
"   >>> (format #t "%d\n" i)
"   >>> (loop (+ i 1))))
"   0
"   1
"   2
"
"   See mosalisp.init() function and trailing script for more
"   information.
"
"
" TODO:
"   - error handling mechanism

let s:sfile = expand("<sfile>:p")

let s:lib = {}
let mosalisp = s:lib

function s:lib.repl()
  let save_more = &more
  set nomore
  let self.inbuf = []
  let self.read_nest = 1
  let self.getchar = self.getchar_input
  let self.scope = self.cons(self.top_env, self.NIL)
  let self.stack = [["op_loop", 1, self.NIL]]
  while self.stack[0][0] != "op_exit"
    let op = remove(self.stack, 0)
    try
      call self[op[0]](op)
    catch
      echohl Error
      echo "Exception from" self.get_throwpoint()
      echo v:exception
      echohl None
      break
    endtry
  endwhile
  let &more = save_more
endfunction

function s:lib.load_str(str, ...)
  let self.inbuf = split(a:str, '\zs')
  let self.getchar = self.getchar_str
  let self.scope = self.cons(self.top_env, self.NIL)
  let self.stack = [["op_loop", 0, self.NIL]]
  while self.stack[0][0] != "op_exit"
    let op = remove(self.stack, 0)
    try
      call self[op[0]](op)
    catch
      echohl Error
      echo "Exception from" self.get_throwpoint()
      echo v:exception
      echohl None
      break
    endtry
  endwhile
  let res = self.stack[0][1]
  return get(a:000, 0, 0) ? res : self.to_vimobj(res)
endfunction

function s:lib.load(fname, ...)
  return self.load_str(join(readfile(a:fname), "\n"), get(a:000, 0, 0))
endfunction

function s:lib.dump_env()
  let p = self.scope
  while p.type == "pair"
    let hash = p.car.val
    for name in sort(keys(hash))
      let item = hash[name]
      echo printf("%s [%s]", name, item.type)
    endfor
    let p = p.cdr
  endwhile
endfunction

function s:lib.get_funcname(number)
  for name in keys(self)
    if type(self[name]) == type(function("tr"))
      let s = string(self[name])
      if s =~ printf("'%d'", a:number)
        return name
      endif
    endif
  endfor
  return a:number
endfunction

function s:lib.get_throwpoint()
  return substitute(v:throwpoint, '\d\+\ze\.\.\|\.\.\zs\d\+', '\=self.get_funcname(submatch(0))', 'g')
endfunction

" {{{ read
function s:lib.read()
  call self.skip_blank()
  let c = self.peekchar()
  if c == "eof"
    return self.Undefined
  elseif c == '('
    let self.read_nest += 1
    let res = self.read_list()
    let self.read_nest -= 1
    return res
  elseif c == '"'
    return self.read_string()
  elseif c =~ '\d' || c =~ '[-+]' && get(self.inbuf, 1, "") =~ '\d'
    return self.read_number()
  elseif c == '#'
    return self.read_const()
  elseif c == "'" || c == '`'
    return self.read_quote()
  elseif c == ','
    return self.read_unquote()
  else
    return self.read_symbol()
  endif
endfunction

function s:lib.read_list()
  let res = []
  call self.getchar()
  call self.skip_blank()
  while self.peekchar() != ')'
    if self.peekchar() == "eof"
      throw "eof"
    elseif self.peekchar() == "."
      call self.getchar()
      call self.skip_blank()
      call add(res, self.read())
      call self.skip_blank()
      call self.getchar()  " skip ')'
      let lis = self.mk_list(res)
      let p = lis
      while 1
        if p.cdr.cdr == self.NIL
          let p.cdr = p.cdr.car
          break
        endif
        let p = p.cdr
      endwhile
      return lis
    endif
    call add(res, self.read())
    call self.skip_blank()
  endwhile
  call self.getchar()
  return self.mk_list(res)
endfunction

function s:lib.read_string()
  let res = self.getchar()
  while self.peekchar() != '"'
    if self.peekchar() == "eof"
      throw "eof"
    elseif self.peekchar() == '\'
      let res .= self.getchar() . self.getchar()
    else
      let res .= self.getchar()
    endif
  endwhile
  let res .= self.getchar()
  return self.mk_string(eval(res))
endfunction

function s:lib.read_number()
  let res = self.getchar()
  while self.peekchar() !~ 'eof\|[() \t\n]'
    let res .= self.getchar()
  endwhile
  return self.mk_number(eval(res))
endfunction

function s:lib.read_const()
  call self.getchar()
  let c = self.getchar()
  if c == 'f'
    return self.False
  elseif c == 't'
    return self.True
  elseif c == 'o'
    let res = ""
    while self.peekchar() =~ '\o'
      let res .= self.getchar()
    endwhile
    return self.mk_number(str2nr(re, 8))
  elseif c == 'd'
    let res = ""
    while self.peekchar() =~ '\d'
      let res .= self.getchar()
    endwhile
    return self.mk_number(str2nr(res, 10))
  elseif c == 'x'
    let res = ""
    while self.peekchar() =~ '\x'
      let res .= self.getchar()
    endwhile
    return self.mk_number(str2nr(res, 16))
  endif
endfunction

function s:lib.read_symbol()
  let res = ""
  while self.peekchar() !~ 'eof\|[() \t\n]'
    let res .= self.getchar()
  endwhile
  return self.mk_symbol(res)
endfunction

function s:lib.read_quote()
  let res = [self.mk_symbol(self.getchar() == "'" ? 'quote' : 'quasiquote')]
  call add(res, self.read())
  return self.mk_list(res)
endfunction

function s:lib.read_unquote()
  call self.getchar()
  if self.peekchar() == '@'
    call self.getchar()
    let res = [self.mk_symbol('unquote-splicing')]
  else
    let res = [self.mk_symbol('unquote')]
  endif
  call add(res, self.read())
  return self.mk_list(res)
endfunction

function s:lib.skip_comment()
  while self.getchar() !~ 'eof\|\n'
    " pass
  endwhile
endfunction

function s:lib.skip_blank()
  while self.peekchar() =~ '\_s'
    call self.getchar()
  endwhile
  if self.peekchar() == ';'
    call self.skip_comment()
    call self.skip_blank()
  endif
endfunction

function s:lib.peekchar()
  if empty(self.inbuf)
    let c = self.getchar()
    call self.putchar(c)
  else
    let c = self.inbuf[0]
  endif
  return c
endfunction

function s:lib.getchar_input()
  if self.inbuf == []
    let prefix = repeat(">", self.read_nest) . " "
    try
      let str = input(prefix)
    catch /Vim:Interrupt/
      let self.inbuf = ["eof"]
      return "eof"
    endtry
    echon printf("\r%s%s\n", prefix, str)
    let self.inbuf = split(str, '\zs') + ["\n"]
    return self.getchar_input()
  endif
  if self.inbuf[0] == "eof"
    return "eof"
  endif
  return remove(self.inbuf, 0)
endfunction

function s:lib.getchar_str()
  if self.inbuf == []
    return "eof"
  endif
  return remove(self.inbuf, 0)
endfunction

function s:lib.putchar(c)
  if a:c != "eof"
    call insert(self.inbuf, a:c)
  endif
endfunction
" }}}

" {{{ eval

function s:lib.mk_symbol(str)
  if !has_key(self.symbol_table, a:str)
    let self.symbol_table[a:str] = {"type":"symbol", "val":a:str}
  endif
  return self.symbol_table[a:str]
endfunction

function s:lib.mk_number(num)
  return {"type":"number", "val":a:num}
endfunction

function s:lib.mk_string(str)
  return {"type":"string", "val":a:str}
endfunction

function s:lib.mk_hash(hash)
  return {"type":"hash", "val":a:hash}
endfunction

function s:lib.mk_vim_function(func)
  return {"type":"procedure", "val":"f_vim_function", "func":a:func}
endfunction

function s:lib.mk_list(lst)
  let p = self.NIL
  for item in a:lst
    let p = self.cons(item, p)
  endfor
  return self.reverse(p)
endfunction

" lisp function
function s:lib.mk_closure(type, args, code)
  return {
        \ "type": a:type,
        \ "val": "f_closure",
        \ "scope": self.scope,
        \ "args": a:args,
        \ "code": a:code
        \ }
endfunction

" embedded vim function
function s:lib.mk_procedure(type, args, expr)
  return {
        \ "type": a:type,
        \ "val": "f_procedure",
        \ "scope": self.scope,
        \ "args": a:args,
        \ "expr": a:expr
        \ }
endfunction

function s:lib.mk_continuation()
  return {
        \ "type": "continuation",
        \ "val": "f_continue",
        \ "scope": self.scope,
        \ "stack": map(copy(self.stack), 'copy(v:val)')
        \ }
endfunction

function s:lib.cons(car, cdr)
  return {"type":"pair", "car":a:car, "cdr":a:cdr}
endfunction

function s:lib.reverse(cell)
  let p = self.NIL
  let x = a:cell
  while x.type == "pair"
    let p = self.cons(x.car, p)
    let x = x.cdr
  endwhile
  return p
endfunction

function s:lib.copylist(obj, noref, nest, newobj)
  if a:obj.type != 'pair'
    return [a:obj, {}]
  elseif self.obj_index(a:nest, a:obj) != -1
    let n = self.obj_index(a:nest, a:obj)
    return [a:newobj[n], {}]
  endif
  let res = copy(a:obj)
  call add(a:nest, a:obj)
  call add(a:newobj, res)
  let p = res
  while p.cdr.type == "pair" && self.obj_index(a:nest, p.cdr) == -1
    call add(a:nest, p.cdr)
    let p.cdr = copy(p.cdr)
    call add(a:newobj, p.cdr)
    let p = p.cdr
  endwhile
  if p.cdr.type == "pair"   " means self.obj_index(a:nest, p.cdr) != -1
    let n = self.obj_index(a:nest, p.cdr)
    let p.cdr = a:newobj[n]
  endif
  let lastcell = p
  if a:noref
    let p = res
    while p isnot lastcell
      if p.car.type == "pair"
        let p.car = self.copylist(p.car, a:noref, a:nest, a:newobj)[0]
      endif
      let p = p.cdr
    endwhile
    if p.cdr.type == "pair"
      let p.cdr = self.copylist(p.cdr, a:noref, a:nest, a:newobj)[0]
    endif
  endif
  return [res, lastcell]
endfunction

function s:lib.op_read(op)
  call add(self.stack[0], self.read())
endfunction

function s:lib.op_eval(op)
  let code = a:op[1]
  if code.type == "symbol"
    let [env, val] = self.findscope(self.scope, code.val)
    if env != {}
      call add(self.stack[0], val)
    else
      call self.error(printf("Unbounded Variable: %s", code.val))
    endif
  elseif code.type == "pair"
    call insert(self.stack, ["op_call", code, code.cdr])
    call insert(self.stack, ["op_eval", code.car])
  else
    call add(self.stack[0], code)
  endif
endfunction

function s:lib.op_print(op)
  let value = a:op[1]
  if value.type != "undefined"
    echo "=>" self.to_str(a:op[1])
  endif
  call add(self.stack[0], a:op[1])
endfunction

function s:lib.op_loop(op)
  let [do_print, ret] = a:op[1:]
  if self.peekchar() == "eof"
    call insert(self.stack, ["op_exit", ret])
    return
  endif
  call insert(self.stack, ["op_loop", do_print])
  if do_print
    call insert(self.stack, ["op_print"])
  endif
  call insert(self.stack, ["op_eval"])
  call insert(self.stack, ["op_read"])
endfunction

function s:lib.op_error(op)
  let args = a:op[1]
  echohl Error
  echo args.car.val
  echohl None
  call insert(self.stack, ["op_exit", self.NIL])
endfunction

function s:lib.op_call(op)
  let [orig, code, func] = a:op[1:]
  if func.type == "macro"
    call insert(self.stack, ["op_eval"])
    call insert(self.stack, ["op_macro_replace", orig])
    call insert(self.stack, ["op_apply", func, code])
  elseif func.type == "syntax"
    call insert(self.stack, ["op_apply", func, code])
  else
    if code == self.NIL
      call insert(self.stack, ["op_apply", func, self.NIL])
    else
      call insert(self.stack, ["op_apply", func])
      call insert(self.stack, ["op_args", code.cdr, self.NIL])
      call insert(self.stack, ["op_eval", code.car])
    endif
  endif
endfunction

function s:lib.op_args(op)
  let [code, args, arg] = a:op[1:]
  let args = self.cons(arg, args)
  if code == self.NIL
    call add(self.stack[0], self.reverse(args))
  else
    call insert(self.stack, ["op_args", code.cdr, args])
    call insert(self.stack, ["op_eval", code.car])
  endif
endfunction

function s:lib.op_apply(op)
  let [func, args] = a:op[1:]
  call self[func.val](func, args)
endfunction

function s:lib.op_macro_replace(op)
  let [orig, code] = a:op[1:]
  call self.obj_replace(orig, code)
  call add(self.stack[0], code)
endfunction

function s:lib.op_return(op)
  let self.scope = a:op[1]
  call add(self.stack[0], a:op[2])
endfunction

function s:lib.op_define(op)
  call self.define(a:op[1], a:op[2])
  call add(self.stack[0], self.Undefined)
endfunction

function s:lib.op_set(op)
  let [name, value] = a:op[1:]
  let [env, val] = self.findscope(self.scope, name)
  if env != {}
    let env[name] = value
    call add(self.stack[0], self.Undefined)
  else
    call self.error(printf("Unbounded Variable: %s", name))
  endif
endfunction

function s:lib.op_if(op)
  let [t, f, cond] = a:op[1:]
  call insert(self.stack, ["op_eval", (cond != self.False) ? t : f])
endfunction

function s:lib.op_cond(op)
  let [code, expr, cond] = a:op[1:]
  if cond != self.False
    if expr == self.NIL
      " (test)
      call add(self.stack[0], cond)
    elseif expr.car.type == 'symbol' && expr.car.val == '=>'
      " (test => proc)
      let proc = expr.cdr.car
      call insert(self.stack, ['op_eval', self.cons(proc, self.cons(cond, self.NIL))])
    else
      " (test expr ...)
      call self.begin(expr)
    endif
  else
    if code == self.NIL
      call add(self.stack[0], self.Undefined)
    elseif code.car.car.type == "symbol" && code.car.car.val == "else"
      call insert(self.stack, ["op_cond", self.NIL, code.car.cdr, self.True])
    else
      call insert(self.stack, ["op_cond", code.cdr, code.car.cdr])
      call insert(self.stack, ["op_eval", code.car.car])
    endif
  endif
endfunction

function s:lib.op_or(op)
  let [code, cond] = a:op[1:]
  if cond != self.False
    call add(self.stack[0], cond)
  elseif code == self.NIL
    call add(self.stack[0], cond)
  else
    call insert(self.stack, ["op_or", code.cdr])
    call insert(self.stack, ["op_eval", code.car])
  endif
endfunction

function s:lib.op_and(op)
  let [code, cond] = a:op[1:]
  if !(cond != self.False)    " (not cond)
    call add(self.stack[0], cond)
  elseif code == self.NIL
    call add(self.stack[0], cond)
  else
    call insert(self.stack, ["op_and", code.cdr])
    call insert(self.stack, ["op_eval", code.car])
  endif
endfunction

function s:lib.error(msg)
  let args = self.mk_list([self.mk_string(a:msg)])
  call insert(self.stack, ["op_error", args])
endfunction

function s:lib.define(name, obj)
  let hash = self.scope.car.val
  let hash[a:name] = a:obj
endfunction

function s:lib.findscope(scope, name)
  let p = a:scope
  while p.type == "pair"
    let hash = p.car.val
    if has_key(hash, a:name)
      return [hash, hash[a:name]]
    endif
    let p = p.cdr
  endwhile
  return [{}, {}]
endfunction

function s:lib.begin(code)
  let i = 0
  let p = a:code
  while p.type == "pair"
    call insert(self.stack, ["op_eval", p.car], i)
    let i += 1
    let p = p.cdr
  endwhile
endfunction

function s:lib.f_closure(this, args)
  let [this, args] = [a:this, a:args]
  if self.stack[0][0] != "op_return"
    call insert(self.stack, ["op_return", self.scope])
  endif
  let self.scope = self.cons(self.mk_hash({}), this.scope)

  " expand arguments
  let p = this.args
  while p.type == "pair"
    call self.define(p.car.val, args.car)
    let [p, args] = [p.cdr, args.cdr]
  endwhile
  if p != self.NIL
    call self.define(p.val, args)
  endif

  call self.begin(this.code)
endfunction

function s:lib.f_procedure(this, args)
  let [_this, _args] = [a:this, a:args]
  let _expr = _this.expr

  " expand arguments
  let _p = _this.args
  let _a = _args
  while _p.type == "pair"
    execute printf("let %s = _a.car", _p.car.val)
    let _p = _p.cdr
    let _a = _a.cdr
  endwhile
  if _p != self.NIL
    execute printf("let %s = _a", _p.val)
  endif

  execute _expr
  if exists("_res")
    call add(self.stack[0], _res)
  endif
endfunction

function s:lib.f_continue(this, args)
  let self.stack = map(copy(a:this.stack), 'copy(v:val)')
  let self.scope = a:this.scope
  call add(self.stack[0], (a:args == self.NIL) ? self.NIL : a:args.car)
endfunction

function s:lib.f_vim_function(this, args)
  " vim function wrapper
  let args = self.to_vimobj(a:args)
  let VimObj = call(a:this.func, args)
  call add(self.stack[0], self.to_lispobj(VimObj))
endfunction

function s:lib.to_str(obj)
  if a:obj.type == "undefined"       | return "#<undefined>"
  elseif a:obj.type == "NIL"         | return "()"
  elseif a:obj.type == "boolean"     | return (a:obj.val ? "#t" : "#f")
  elseif a:obj.type == "number"      | return string(a:obj.val)
  elseif a:obj.type == "string"      | return string(a:obj.val)
  elseif a:obj.type == "symbol"      | return a:obj.val
  elseif a:obj.type == "hash"        | return "#<hash>"
  elseif a:obj.type == "pair"        | return self.to_str_pair(a:obj, [])
  elseif a:obj.type == "closure"     | return "#<closure>"
  elseif a:obj.type == "continuation"| return "#<continuation>"
  elseif a:obj.type == "procedure"   | return "#<procedure>"
  elseif a:obj.type == "syntax"      | return "#<syntax>"
  elseif a:obj.type == "macro"       | return "#<macro>"
  endif
endfunction

function s:lib.to_vimobj(obj)
  if a:obj.type == "undefined"       | return a:obj.val
  elseif a:obj.type == "NIL"         | return a:obj.val
  elseif a:obj.type == "boolean"     | return a:obj.val
  elseif a:obj.type == "number"      | return a:obj.val
  elseif a:obj.type == "string"      | return a:obj.val
  elseif a:obj.type == "symbol"      | return a:obj.val
  elseif a:obj.type == "hash"        | return a:obj.val
  elseif a:obj.type == "pair"        | return self.to_vimobj_pair(a:obj, [], [])
  elseif a:obj.type == "closure"     | return a:obj
  elseif a:obj.type == "continuation"| return a:obj
  elseif a:obj.type == "procedure"   | return a:obj
  elseif a:obj.type == "syntax"      | return a:obj
  elseif a:obj.type == "macro"       | return a:obj
  endif
endfunction

function s:lib.to_lispobj(obj)
  if type(a:obj) == type(0)          | return self.mk_number(a:obj)
  elseif type(a:obj) == type("")     | return self.mk_string(a:obj)
  elseif type(a:obj) == type({})     | return self.mk_hash(a:obj)
  elseif type(a:obj) == type([])     | return self.to_lispobj_pair(a:obj, [], [])
  elseif type(a:obj) == type(function("tr")) | return self.mk_vim_function(a:obj)
  endif
endfunction

function s:lib.to_str_pair(obj, nest)
  if self.obj_index(a:nest, a:obj) != -1
    let n = self.obj_index(a:nest, a:obj)
    return printf("#%d(...)", n)
  endif
  let p = a:obj
  while p.type == "pair" && self.obj_index(a:nest, p) == -1
    call add(a:nest, p)
    let p = p.cdr
  endwhile
  let tail = p
  let res = []
  let p = a:obj
  while p isnot tail
    if p.car.type == "pair"
      call add(res, self.to_str_pair(p.car, a:nest))
    else
      call add(res, self.to_str(p.car))
    endif
    let p = p.cdr
  endwhile
  if p != self.NIL    " improper list
    call add(res, ".")
    if p.type == "pair"
      call add(res, self.to_str_pair(p, a:nest))
    else
      call add(res, self.to_str(p))
    endif
  endif
  return '(' . join(res) . ')'
endfunction

function s:lib.to_vimobj_pair(obj, nest, vimobj)
  " Improper list is converted to proper list because Vim does not
  " support it.
  " Vim does not support List like this
  " (define x (list 1 2 3 4 5))
  " (set-car! x (cdr x))
  if self.obj_index(a:nest, a:obj) != -1
    let n = self.obj_index(a:nest, a:obj)
    return a:vimobj[n]
  endif
  let res = []
  call add(a:nest, a:obj)
  call add(a:vimobj, res)
  let p = a:obj
  while p.cdr.type == "pair" && self.obj_index(a:nest, p.cdr) == -1
    call add(a:nest, p.cdr)
    call add(a:vimobj, [])  " can't link non-top cons cell
    let p = p.cdr
  endwhile
  let tail = p.cdr
  let p = a:obj
  while p isnot tail
    if p.car.type == "pair"
      call add(res, self.to_vimobj_pair(p.car, a:nest, a:vimobj))
    else
      call add(res, self.to_vimobj(p.car))
    endif
    let p = p.cdr
  endwhile
  if p != self.NIL    " improper list
    if p.type == "pair"
      call add(res, self.to_vimobj_pair(p, a:nest, a:vimobj))
    else
      call add(res, self.to_vimobj(p))
    endif
  endif
  return res
endfunction

function s:lib.to_lispobj_pair(obj, nest, lispobj)
  if self.obj_index(a:nest, a:obj) != -1
    let n = self.obj_index(a:nest, a:obj)
    return a:lispobj[n]
  endif
  let res = {}  " place holder
  let r = self.NIL
  call add(a:nest, a:obj)
  call add(a:lispobj, res)
  for p in a:obj
    if type(p) == type([])
      let r = self.cons(self.to_lispobj_pair(p, a:nest, a:lispobj), r)
    else
      let r = self.cons(self.to_lispobj(p), r)
    endif
    unlet p     " avoid "E706: Variable type mismatch for: p"
  endfor
  return self.obj_replace(res, self.reverse(r))
endfunction

function s:lib.obj_index(lst, obj)
  let i = 0
  for o in a:lst
    if o is a:obj
      return i
    endif
    let i += 1
  endfor
  return -1
endfunction

function s:lib.obj_replace(lhs, rhs)
  for key in keys(a:lhs)
    unlet a:lhs[key]
  endfor
  return extend(a:lhs, a:rhs)
endfunction

" }}}

function s:lib.init()
  let self.inbuf = []
  let self.read_nest = 1
  let self.symbol_table = {}
  let self.top_env = self.mk_hash({})

  " constant
  let self.Undefined = {"type":"undefined", "val":["#<undefined>"]}
  let self.NIL = {"type":"NIL", "val":[]}
  let self.False = {"type":"boolean", "val":0}
  let self.True  = {"type":"boolean", "val":1}
  lockvar self.Undefined
  lockvar self.NIL
  lockvar self.False
  lockvar self.True

  " register
  let self.scope = self.cons(self.top_env, self.NIL)
  let self.stack = []

  let args = self.cons(self.mk_symbol("var"), self.mk_symbol("expr"))
  let expr = "if var.type == 'pair'\n"
        \  . "  call insert(self.stack, ['op_define', self.to_vimobj(var.car), self.mk_closure('closure', var.cdr, expr)])\n"
        \  . "else\n"
        \  . "  call insert(self.stack, ['op_define', self.to_vimobj(var)])\n"
        \  . "  call insert(self.stack, ['op_eval', expr.car])\n"
        \  . "endif\n"
  call self.define("define", self.mk_procedure('syntax', args, expr))

  let args = self.mk_list([self.mk_symbol("args"), self.mk_symbol("expr")])
  let expr = "let _res = self.mk_procedure('syntax', args, self.to_vimobj(expr))\n"
  call self.define("%vim-syntax", self.mk_procedure('syntax', args, expr))

  " load init script
  echo "loading init script ..."
  let lines = readfile(s:sfile)
  let start = index(lines, "mzscheme <<EOF") + 1
  let end = index(lines, "EOF", start + 1) - 1
  call self.load_str(join(lines[start : end], "\n"))
  echo "done"
endfunction

call s:lib.init()

finish
mzscheme <<EOF
;; init script
;; "mzscheme <<EOF" is only used for highlighting.

(define %vim-proc
  (%vim-syntax (args expr)
    "let _res = self.mk_procedure('procedure', args, self.to_vimobj(expr))"))

(define %set-attr
  (%vim-proc (obj name value)
    "let obj[self.to_vimobj(name)] = value
     let _res = self.Undefined"))

(define %get-attr
  (%vim-proc (obj name . default)
    "let default = (default == self.NIL) ? self.Undefined : default.car
     let _res = get(obj, self.to_vimobj(name), default)"))

(define %get-type
  (%vim-proc (obj)
    "let _res = self.mk_string(obj.type)"))

(define lambda
  (%vim-syntax (args . code)
    "let _res = self.mk_closure('closure', args, code)"))

(define macro
  (%vim-syntax (args . code)
    "let _res = self.mk_closure('macro', args, code)"))

(define %syntax
  (%vim-syntax (args . code)
    "let _res = self.mk_closure('syntax', args, code)"))

(define quote
  (%vim-syntax (obj)
    "let _res = obj"))

(define set!
  (%vim-syntax (name value)
    "call insert(self.stack, ['op_set', self.to_vimobj(name)])
     call insert(self.stack, ['op_eval', value])"))

(define if
  (%vim-syntax (cond t . rest)
    "let f = (rest == self.NIL) ? self.Undefined : rest.car
     call insert(self.stack, ['op_if', t, f])
     call insert(self.stack, ['op_eval', cond])"))

(define cond
  (%vim-syntax code
    "call insert(self.stack, ['op_cond', code, self.False, self.False])"))

(define begin
  (%vim-syntax code
    "if code == self.NIL
       let _res = self.Undefined
     else
       call self.begin(code)
     endif"))

(define or
  (%vim-syntax code
    "call insert(self.stack, ['op_or', code, self.False])"))

(define and
  (%vim-syntax code
    "call insert(self.stack, ['op_and', code, self.True])"))

(define eval
  (%vim-proc (lst)
    "call insert(self.stack, ['op_eval', lst])"))

(define macroexpand-1
  (%vim-proc (lst)
    "let [symbol, code] = [lst.car, lst.cdr]
     let macro = self.findscope(self.scope, symbol.val)[1]
     call insert(self.stack, ['op_apply', macro, code])"))

(define call-with-current-continuation
  (%vim-proc (proc)
    "let cont = self.mk_continuation()
     call insert(self.stack, ['op_apply', proc, self.cons(cont, self.NIL)])"))

(define call/cc call-with-current-continuation)

(define load
  (%vim-proc (filename)
    "let save = [self.inbuf, self.getchar, self.stack]
     let _res = self.load(self.to_vimobj(filename), 1)
     let [self.inbuf, self.getchar, self.stack] = save"))

(define exit
  (%vim-proc args
    "let exitcode = (args == self.NIL) ? self.NIL : args.car
     call insert(self.stack, ['op_exit', exitcode])"))

(define error
  (%vim-proc (msg . args)
    "call insert(self.stack, ['op_error', self.cons(msg, args)])"))

(define list
  (%vim-proc args
    "let _res = args"))

(define (values . args)
  (if (and (pair? args) (null? (cdr args)))
    (car args)
    (begin
      ;; (or (null? args) (> 1 (length args)))
      ;; NIL is locked and can't be %set-attr.  use new cons cell;
      (set! args (cons '() args))
      (%set-attr args "is-values" #t)
      args)))

(define (call-with-values producer consumer)
  (define res (producer))
  (if (%get-attr res "is-values" #f)
    (apply consumer (cdr res))
    (consumer res)))

;;;;; === dynamic-wind ===
;; http://www.cs.hmc.edu/~fleck/envision/scheme48/meeting/node7.html

(define *here* (list #f))

(define original-cwcc call-with-current-continuation)

(define (call-with-current-continuation proc)
  (let ((here *here*))
    (original-cwcc
      (lambda (cont)
        (proc
          (lambda results
            (reroot! here)
            (apply cont results)))))))

(define call/cc call-with-current-continuation)

(define (dynamic-wind before during after)
  (let ((here *here*))
    (reroot! (cons (cons before after) here))
    (call-with-values
      during
      (lambda results
        (reroot! here)
        (apply values results)))))

(define (reroot! there)
  (if (not (eq? *here* there))
    (begin
      (reroot! (cdr there))
      (let ((before (caar there))
            (after (cdar there)))
        (set-car! *here* (cons after before))
        (set-cdr! *here* there)
        (set-car! there #f)
        (set-cdr! there '())
        (set! *here* there)
        (before)))))
;;;;; === end ===

;;;;; === exception srfi-34 ===
;; http://srfi.schemers.org/srfi-34/srfi-34.html

(define *current-exception-handlers*
  (list (lambda (condition)
          (error "unhandled exception" condition))))

(define (current-exception-handler) (car *current-exception-handlers*))

(define (with-exception-handler handler thunk)
  (with-exception-handlers (cons handler *current-exception-handlers*)
                           thunk))

(define (with-exception-handlers new-handlers thunk)
  (let ((previous-handlers *current-exception-handlers*))
    (dynamic-wind
      (lambda ()
        (set! *current-exception-handlers* new-handlers))
      thunk
      (lambda ()
        (set! *current-exception-handlers* previous-handlers)))))

(define (raise obj)
  (let ((handlers *current-exception-handlers*))
    (with-exception-handlers (cdr handlers)
      (lambda ()
        ((car handlers) obj)
        (error "handler returned"
               (car handlers)
               obj)))))

;;;;; === end ===

(define %echon-port
  (%vim-proc (obj)
    "echon (obj.type == 'string') ? obj.val : self.to_str(obj)
     let _res = self.Undefined"))
(%set-attr %echon-port "is-output-port" #t)

(define %current-output-port %echon-port)

(define (current-output-port)
  %current-output-port)

(define display
  (%vim-proc (obj . rest)
    "let port = (rest == self.NIL) ? self.findscope(self.scope, '%current-output-port')[1] : rest.car
     call insert(self.stack, ['op_apply', port, self.cons(obj, self.NIL)])"))

(define (newline . rest)
  (apply display "\n" rest))

(define %format
  (%vim-proc (fmt args)
    "let lst = [self.to_vimobj(fmt)]
     let p = args
     while p.type == 'pair'
       if p.car.type == 'number' || p.car.type == 'string'
         call add(lst, self.to_vimobj(p.car))
       else
         call add(lst, self.to_str(p.car))
       endif
       let p = p.cdr
     endwhile
     let str = (len(lst) == 1) ? lst[0] : call('printf', lst)
     let _res = self.to_lispobj(str)"))

(define (format port . args)
  ;; (format port fmt . args)
  ;; (format #t fmt . args) => (format (current-output-port) fmt . args)
  ;; (format #f fmt . args) => (%format fmt args)
  ;; (format fmt . args)    => (%format fmt args)
  (if (string? port)
    (begin
      (set! args (cons port args))
      (set! port #f)))
  (cond ((output-port? port) (port (%format (car args) (cdr args))))
        (port ((current-output-port) (%format (car args) (cdr args))))
        (else (%format (car args) (cdr args)))))

(define :call
  (%vim-proc (func . args)
    "unlet func args
     let [func; args] = self.to_vimobj(_args)
     let VimObj = call(func, args)
     let _res = self.to_lispobj(VimObj)"))

(define :execute
  (%vim-proc (expr)
    "execute self.to_vimobj(expr)
     let _res = self.Undefined"))

(define :let
  (%vim-proc (name value)
    "unlet name value
     let [name, VimObj] = self.to_vimobj(_args)
     execute printf('let %s = VimObj', name)
     let _res = self.Undefined"))

(define make-hash-table
  (%vim-proc ()
    "let _res = self.mk_hash({})"))

;; Dictionary is not boxed automatically.
;; Box its value for each access for now.
;; type check is lazy.
(define hash-table-ref
  (%vim-proc (hash key)
    "unlet hash key
     let [hash, key] = self.to_vimobj(_args)
     let Value = hash[key]
     if type(Value) == type({}) && has_key(Value, 'type')
       let _res = Value
     else
       let _res = self.to_lispobj(Value)
     endif"))

(define hash-table-put!
  (%vim-proc (hash key value)
    "unlet hash key
     let hash = self.to_vimobj(_args.car)
     let key = self.to_vimobj(_args.cdr.car)
     let hash[key] = value
     let _res = self.Undefined"))

(define cons
  (%vim-proc (car cdr)
    "let _res = self.cons(car, cdr)"))

(define car
  (%vim-proc (pair)
    "let _res = pair.car"))

(define cdr
  (%vim-proc (pair)
    "let _res = pair.cdr"))

(define set-car!
  (%vim-proc (pair value)
    "let pair.car = value
     let _res = self.Undefined"))

(define set-cdr!
  (%vim-proc (pair value)
    "let pair.cdr = value
     let _res = self.Undefined"))

(define (not value)
  (if value #f #t))

(define undefined
  (%vim-proc ()
    "let _res = self.Undefined"))

(define (%make-cmp op)
  (%vim-proc (lhs rhs . rest)
    "unlet lhs rhs rest
     let op = self.to_vimobj(self.findscope(_this.scope, 'op')[1])
     let [lhs, rhs; rest] = self.to_vimobj(_args)
     let expr = 'lhs ' . op . ' rhs'
     let _res = self.False
     if eval(expr)
       let _res = self.True
       let lhs = rhs
       for rhs in rest
         if !eval(expr)
           let _res = self.False
           break
         endif
         let lhs = rhs
       endfor
     endif"))

(define (%make-cmp-ins op)
  (%vim-proc (lhs rhs . rest)
    "let op = self.to_vimobj(self.findscope(_this.scope, 'op')[1])
     let expr = 'lhs ' . op . ' rhs'
     let _res = self.False
     if eval(expr)
       let _res = self.True
       let lhs = rhs
       while rest.type == 'pair'
         let rhs = rest.car
         let rest = rest.cdr
         if !eval(expr)
           let _res = self.False
           break
         endif
         let lhs = rhs
       endwhile
     endif"))

(define (%make-sum op value-for-unary)
  (%vim-proc args
    "let op = self.to_vimobj(self.findscope(_this.scope, 'op')[1])
     let unary = self.to_vimobj(self.findscope(_this.scope, 'value-for-unary')[1])
     let expr = 'sum ' . op . ' num'
     if args == self.NIL
       let _res = self.to_lispobj(unary)
     else
       let [num; rest] = self.to_vimobj(args)
       if rest == []
         let sum = unary
       else
         let sum = num
         let num = remove(rest, 0)
       endif
       let sum = eval(expr)
       for num in rest
         let sum = eval(expr)
       endfor
       let _res = self.to_lispobj(sum)
     endif"))

(define =   (%make-cmp "=="))
(define ==  (%make-cmp "=="))
(define !=  (%make-cmp "!="))
(define >   (%make-cmp ">"))
(define >=  (%make-cmp ">="))
(define <   (%make-cmp "<"))
(define <=  (%make-cmp "<="))
(define =~  (%make-cmp "=~"))
(define !~  (%make-cmp "!~"))
(define =#  (%make-cmp "==#"))
(define ==# (%make-cmp "==#"))
(define !=# (%make-cmp "!=#"))
(define >#  (%make-cmp ">#"))
(define >=# (%make-cmp ">=#"))
(define <#  (%make-cmp "<#"))
(define <=# (%make-cmp "<=#"))
(define =~# (%make-cmp "=~#"))
(define !~# (%make-cmp "!~#"))
(define =?  (%make-cmp "==?"))
(define ==? (%make-cmp "==?"))
(define !=? (%make-cmp "!=?"))
(define >?  (%make-cmp ">?"))
(define >=? (%make-cmp ">=?"))
(define <?  (%make-cmp "<?"))
(define <=? (%make-cmp "<=?"))
(define =~? (%make-cmp "=~?"))
(define !~? (%make-cmp "!~?"))
(define is  (%make-cmp-ins "is"))
(define isnot (%make-cmp-ins "isnot"))
(define +   (%make-sum "+" 0))
(define -   (%make-sum "-" 0))
(define *   (%make-sum "*" 1))
(define /   (%make-sum "/" 1))
(define %   (%make-sum "%" 1))

(define (procedure? x) (=~ (%get-type x) "procedure\\|closure"))
(define (syntax? x)    (= (%get-type x) "syntax"))
(define (macro? x)     (= (%get-type x) "macro"))
(define (null? x)      (= (%get-type x) "NIL"))
(define (pair? x)      (= (%get-type x) "pair"))
(define (symbol? x)    (= (%get-type x) "symbol"))
(define (boolean? x)   (= (%get-type x) "boolean"))
(define (number? x)    (= (%get-type x) "number"))
(define (string? x)    (= (%get-type x) "string"))
(define (hash? x)      (= (%get-type x) "hash"))
(define (undefined? x) (= (%get-type x) "undefined"))
(define (list? x)      (if (pair? x) (list? (cdr x)) (null? x)))
(define (zero? x)      (= x 0))
(define (positive? x)  (> x 0))
(define (negative? x)  (< x 0))
(define (odd? x)       (= 1 (% x 2)))
(define (even? x)      (= 0 (% x 2)))
(define (abs x)        (if (< x 0) (- x) x))
(define eq? is)
(define (eqv? x y)
  (if (and (or (number? x) (string? x))
           (or (number? y) (string? y)))
      (= x y)
      (eq? x y)))

(define (output-port? port)
  (%get-attr port "is-output-port" #f))

(define let
  (macro code
    (if (list? (car code))
        ; (let ((x xi) (y yi) (z zi)) body ...)
        `((lambda ,(map car (car code))
            ,@(cdr code))
          ,@(map cadr (car code)))
        ; (let loop ((x xi) (y yi) (z zi)) body ...)
        `((lambda ()
            (define ,(cons (car code) (map car (cadr code)))
              ,@(cddr code))
            ,(cons (car code) (map cadr (cadr code))))))))

(define let*
  (macro code
    (define (make args body)
      (if (null? args)
          `(begin ,@body)
          `((lambda ,(list (caar args))
              ,(make (cdr args) body))
            ,@(cdar args))))
    (if (list? (car code))
        ; (let* ((x xi) (y yi) (z zi)) body ...)
        (make (car code) (cdr code))
        ; (let* loop ((x xi) (y yi) (z zi)) body ...)
        (make (cadr code) `((define ,(cons (car code) (map car (cadr code)))
                              ,@(cddr code))
                            ,(cons (car code) (map cadr (cadr code))))))))

(define letrec
  (macro code
    (if (list? (car code))
        ; (letrec ((x xi) (y yi) (z zi)) body ...)
        `((lambda ()
            ,@(map (lambda (arg) `(define ,(car arg) ,@(cdr arg))) (car code))
            ,@(cdr code)))
        ; (letrec loop ((x xi) (y yi) (z zi)) body ...)
        `((lambda ()
            ,@(map (lambda (arg) `(define ,(car arg) ,@(cdr arg))) (cadr code))
            (define ,(cons (car code) (map car (cadr code)))
              ,@(cddr code))
            ,(cons (car code) (map cadr (cadr code))))))))

(define apply
  (%vim-proc (proc arg1 . args)
    "if args == self.NIL
       let args = arg1
     else
       let args = _args.cdr
       let p = args
       while p.cdr.cdr.type == 'pair'
         let p = p.cdr
       endwhile
       let p.cdr = p.cdr.car
     endif
     call insert(self.stack, ['op_apply', proc, args])"))

(define length
  (%vim-proc (lst)
    "let i = 0
     while lst.type == 'pair'
       let i += 1
       let lst = lst.cdr
     endwhile
     let _res = self.to_lispobj(i)"))

(define append
  (%vim-proc (arg1 . rest)
    "if rest == self.NIL
       let _res = arg1
     else
       let [_res, r] = self.copylist(arg1, 0, [], [])
       while rest.cdr != self.NIL
         let [r.cdr, r] = self.copylist(rest.car, 0, [], [])
         let rest = rest.cdr
       endwhile
       let r.cdr = rest.car
     endif"))

(define reverse
  (%vim-proc (lst)
    "let _res = self.reverse(lst)"))

(define when
  (macro code
    `(if ,(car code)
       (begin
         ,@(cdr code)))))

(define unless
  (macro code
    `(if (not ,(car code))
       (begin
         ,@(cdr code)))))

;;;;; === copy from init.scm in minischeme ===
(define (caar x) (car (car x)))
(define (cadr x) (car (cdr x)))
(define (cdar x) (cdr (car x)))
(define (cddr x) (cdr (cdr x)))
(define (caaar x) (car (car (car x))))
(define (caadr x) (car (car (cdr x))))
(define (cadar x) (car (cdr (car x))))
(define (caddr x) (car (cdr (cdr x))))
(define (cdaar x) (cdr (car (car x))))
(define (cdadr x) (cdr (car (cdr x))))
(define (cddar x) (cdr (cdr (car x))))
(define (cdddr x) (cdr (cdr (cdr x))))

(define (map proc arg1 . rest)
  (define (map1 proc lst res)
    (if (null? lst)
      (reverse res)
      (map1 proc (cdr lst) (cons (proc (car lst)) res))))
  (define (loop args res)
    (if (null? (car args))
      (reverse res)
      (loop (map1 cdr args '())
            (cons (apply proc (map1 car args '())) res))))
  (if (null? rest)
    (map1 proc arg1 '()) ;; for efficiency
    (loop (cons arg1 rest) '())))

(define (for-each proc arg1 . rest)
  (apply map proc arg1 rest)
  (undefined))

(define (list-tail x k)
    (if (zero? k)
        x
        (list-tail (cdr x) (- k 1))))

(define (list-ref x k)
    (car (list-tail x k)))

(define (last-pair x)
    (if (pair? (cdr x))
        (last-pair (cdr x))
        x))

(define (head stream) (car stream))

(define (tail stream) (force (cdr stream)))

;; The following quasiquote macro is due to Eric S. Tiedemann.
;;   Copyright 1988 by Eric S. Tiedemann; all rights reserved.
;; 
;; --- If you don't use macro or quasiquote, cut below. ---

(define quasiquote
 (macro (l)
   (define (mcons f l r)
     (if (and (pair? r)
              (eq? (car r) 'quote)
              (eq? (car (cdr r)) (cdr f))
              (pair? l)
              (eq? (car l) 'quote)
              (eq? (car (cdr l)) (car f)))
         (list 'quote f)
         (list 'cons l r)))
   (define (mappend f l r)
     (if (or (null? (cdr f))
             (and (pair? r)
                  (eq? (car r) 'quote)
                  (eq? (car (cdr r)) '())))
         l
         (list 'append l r)))
   (define (foo level form)
     (cond ((not (pair? form)) (list 'quote form))
           ((eq? 'quasiquote (car form))
            (mcons form ''quasiquote (foo (+ level 1) (cdr form))))
           (#t (if (zero? level)
                   (cond ((eq? (car form) 'unquote) (car (cdr form)))
                         ((eq? (car form) 'unquote-splicing)
                          (error "Unquote-splicing wasn't in a list:" 
                                 form))
                         ((and (pair? (car form)) 
                               (eq? (car (car form)) 'unquote-splicing))
                          (mappend form (car (cdr (car form))) 
                                   (foo level (cdr form))))
                         (#t (mcons form (foo level (car form))
                                         (foo level (cdr form)))))
                   (cond ((eq? (car form) 'unquote) 
                          (mcons form ''unquote (foo (- level 1) 
                                                     (cdr form))))
                         ((eq? (car form) 'unquote-splicing)
                          (mcons form ''unquote-splicing
                                      (foo (- level 1) (cdr form))))
                         (#t (mcons form (foo level (car form))
                                         (foo level (cdr form)))))))))
   (foo 0 l)))

;;;;; following part is written by a.k

;;;;	atom?
(define (atom? x)
  (not (pair? x)))

;;;;	memq
(define (memq obj lst)
  (cond
    ((null? lst) #f)
    ((eq? obj (car lst)) lst)
    (else (memq obj (cdr lst)))))

;;;;    equal?
(define (equal? x y)
  (if (pair? x)
    (and (pair? y)
         (equal? (car x) (car y))
         (equal? (cdr x) (cdr y)))
    (and (not (pair? y))
         (eqv? x y))))

;;;;	(do ((var init inc) ...) (endtest result ...) body ...)
;;
(define do
  (macro (vars endtest . body)
    (let ((do-loop '%do-loop))
      `(letrec ((,do-loop
                  (lambda ,(map (lambda (x)
                                  (if (pair? x) (car x) x))
                             `,vars)
                    (if ,(car endtest)
                      (begin ,@(cdr endtest))
                      (begin
                        ,@body
                        (,do-loop
                          ,@(map (lambda (x)
                                   (cond
                                     ((not (pair? x)) x)
                                     ((< (length x) 3) (car x))
                                     (else (car (cdr (cdr x))))))
                              `,vars)))))))
         (,do-loop
           ,@(map (lambda (x)
                    (if (and (pair? x) (cdr x))
                      (car (cdr x))
                      '()))
               `,vars))))))
;;;;; === end ===

;;;;; === test ===
(define (test1)
  (define (endless n) (format #t "%d\n" n) (endless (+ n 1)))
  (endless 0))

(define (test2)
  (define (x n) (format #t "x: %d\n" n) (y (+ n 1)))
  (define (y n) (format #t "y: %d\n" n) (z (+ n 1)))
  (define (z n) (format #t "z: %d\n" n) (x (+ n 1)))
  (x 0))

(define (test3)
  (define cc #f)
  (define n (call/cc (lambda (k) (set! cc k) 0)))
  (if (< n 10) (begin (format #t "%d\n" n) (cc (+ n 1)))))

(define (test4)
  ;; recursive list -> string
  (define x (list "x!"))
  (define y (list "y!" #f "x!" x))
  (set-cdr! x x)
  (set-car! (cdr y) y)
  (display y)(newline))

(define (test5)
  (define colors (list "red" "green" "blue" "yellow" "magenta"))
  (set-cdr! (last-pair colors) colors)
  (for-each
    (lambda (c)
      (define color (car colors))
      (set! colors (cdr colors))
      (:execute "hi clear TempColor")
      (:execute (format "hi TempColor guifg=%s ctermfg=%s" color color))
      (:execute "echohl TempColor")
      (display c)
      (:execute "echohl None"))
    (:call "split" "mosalisp!" "\\zs")))

(define (test6)
  ;; values
  (call-with-values (lambda () (values))
                    (lambda () (display "null values\n")))
  (display (call-with-values (lambda () (values 4 5))
                             (lambda (a b) b))) ;; => 5
  (newline)
  (display (call-with-values * -)) ;; => -1
  (newline)
  )

(define (test7)
  ;; dynamic-wind
  (define cont #f)
  (dynamic-wind
    (lambda () (display "1: before\n"))
    (lambda () (display "1: thunk\n"))
    (lambda () (display "1: after\n")))
  (if (call/cc (lambda (c) (set! cont c) #t))
    (dynamic-wind
      (lambda () (display "2: before\n"))
      (lambda () (display "2: thunk\n") (cont #f))
      (lambda () (display "2: after\n"))))
  (if (dynamic-wind
        (lambda () (display "3: before\n"))
        (lambda ()
          (display "3: thunk\n")
          (call/cc (lambda (c) (set! cont c) #t)))
        (lambda () (display "3: after\n")))
      (cont #f))
  )

(define (test8)
  (display
    (call-with-current-continuation
      (lambda (k)
        (with-exception-handler (lambda (x)
                                (display "condition: ")
                                (display x)
                                (newline)
                                (k 'exception))
        (lambda ()
          (+ 1 (raise 'an-error)))))))
  )

(define (fact n)
  (if (<= n 1)
      1
      (* n (fact (- n 1)))))

(define (fib n)
  (if (<= n 1)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))

(define (str->hex str)
  (define (str-len str) (:call "strlen" str))
  (define (str-ref str n) (:call "strpart" str n 1))
  (define (str-ref-hex str n)
    (format "%02X" (:call "char2nr" (str-ref str n))))
  (let loop ((i 0) (res '()))
    (if (>= i (str-len str))
      (:call "join" (reverse res) "")
      (loop (+ i 1) (cons (str-ref-hex str i) res)))))

EOF

" vim:set foldmethod=marker:
