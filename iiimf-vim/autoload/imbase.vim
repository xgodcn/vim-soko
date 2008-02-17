" 2007-02-11

scriptencoding utf-8

let s:cpo_save = &cpo
set cpo&vim

function imbase#import()
  return s:lib
endfunction

let s:lib = {}
let s:lib.api = {}
let s:lib.context = {}
let s:lib.kmod = {}
let s:lib.kmap = {}

"-----------------------------------------------------------
" LOW LEVEL API
let s:lib.api.dll = ""

function s:lib.api.libcall(func, args)
  let EOV = "\x01"   " End Of Value
  let EOV_split = '[\x01]'
  let args = empty(a:args) ? "" : (join(a:args, EOV) . EOV)
  let buf = libcall(self.dll, a:func, args)
  if &encoding != "utf-8"
    " TODO: where is best to conversion.  in dll?  more later?
    let buf = iconv(buf, "utf-8", &encoding)
  endif
  if &encoding =~ 'euc'
    " Vim cannot handle 3 byte EUC char (0x8F [A1-FE] [A1-FE]).
    " Replace it.
    let buf = substitute(buf, '\%x8F.', '?', 'g')
  endif
  " why this does not work?
  " let res = split(buf, EOV, 1)
  let res = split(buf, EOV_split, 1)
  if !empty(res) && res[-1] != ""
    let self.lasterror = res
    throw printf("libcall: %s: %s: %s", fnamemodify(self.dll, ":t"), a:func, string(res))
  endif
  return res[:-2]
endfunction

function s:lib.api.str2hex(str)
  return join(map(range(len(a:str)), 'printf("%02X", char2nr(a:str[v:val]))'), "")
endfunction

function s:lib.api.hex2str(hd)
  " Since Vim can not handle \x00 byte, remove it.
  " do not use nr2char()
  " nr2char(255) => "\xc3\xbf" (utf8)
  return join(map(split(a:hd, '..\zs'), 'v:val == "00" ? "" : eval(''"\x'' . v:val . ''"'')'), "")
endfunction

function s:lib.api.load()
  return self.libcall("load", [self.dll])
endfunction

function s:lib.api.unload()
  return self.libcall("unload", [])
endfunction

function s:lib.api.init()
  return self.libcall("init", [])
endfunction

function s:lib.api.uninit()
  return self.libcall("uninit", [])
endfunction

function s:lib.api.get_imlist()
  return self.libcall("get_imlist", [])
endfunction

function s:lib.api.create_context(method, lang)
  return self.libcall("create_context", [a:method, a:lang])
endfunction

function s:lib.api.delete_context(cx)
  return self.libcall("delete_context", [a:cx])
endfunction

function s:lib.api.send_key(cx, code, mod, raw)
  return self.libcall("send_key", [a:cx, a:code, a:mod, a:raw])
endfunction

"-----------------------------------------------------------
" Input Method
let s:lib.initialized = 0
let s:lib.context_list = []

function s:lib.init()
  if !self.initialized
    call self.api.load()
    call self.api.init()
    let self.initialized = 1
  endif
endfunction

function s:lib.uninit()
  if self.initialized
    for cx in self.context_list
      call cx.delete()
    endfor
    let self.context_list = []
    call self.api.uninit()
    call self.api.unload()
    let self.initialized = 0
  endif
endfunction

function s:lib.get_context(method, lang)
  let [method, lang] = self.find_im(a:method, a:lang)
  let cache_id = method . lang
  for cx in self.context_list
    if cx.cache_id ==? cache_id
      return cx
    endif
  endfor
  let cx = self.context.new(method, lang)
  let cx.cache_id = cache_id
  call add(self.context_list, cx)
  return cx
endfunction

function s:lib.find_im(method, lang)
  let imlist = self.get_imlist()
  for [method, langs, desc, is_default] in imlist
    if a:method == "" && a:lang == ""
      if is_default
        return [method, langs[0]]
      endif
    elseif a:method != "" && a:lang != ""
      if method ==? a:method && index(langs, a:lang) != -1
        return [method, a:lang]
      endif
    elseif a:method != ""
      if method ==? a:method
        return [method, langs[0]]
      endif
    elseif a:lang != ""
      if index(langs, a:lang) != -1
        return [method, a:lang]
      endif
    endif
  endfor
  if a:method == "" && a:lang == ""
    " for iiimf
    for [method, langs, desc, is_default] in imlist
      try
        let cx = self.context.new(method, langs[0])
        call cx.delete()
        return [method, langs[0]]
      catch
        " try next
      endtry
    endfor
  endif
  throw "cannot select input method"
endfunction

function s:lib.get_imlist()
  let imlist = []
  let lis = self.api.get_imlist()
  while !empty(lis)
    let [method, langs_str, desc, is_default] = remove(lis, 0, 3)
    let langs = []
    " langs_str is [,:] separated list.
    for loc in split(langs_str, '[,:]')
      " loc is ja or ja_JP or ja_JP.UTF-8 form.
      let [lang, enc] = matchlist(loc, '\v^(.{-})%(\.(.*))?$')[1:2]
      if index(langs, lang) == -1 && (enc == "" || enc == "UTF-8")
        call add(langs, lang)
      endif
    endfor
    if langs == []
      let langs = [""]
    endif
    if is_default
      call insert(imlist, [method, langs, desc, is_default])
    else
      call add(imlist, [method, langs, desc, is_default])
    endif
  endwhile
  return imlist
endfunction

"-----------------------------------------------------------
" Input Method Context
let s:lib.context.api = {}
let s:lib.context.kmap = {}
let s:lib.context.handle = 0
let s:lib.context.method = ""
let s:lib.context.lang = ""
let s:lib.context.status_label = ""
let s:lib.context.preedit = []
let s:lib.context.candidate = []
let s:lib.context.candidate_current = 0
let s:lib.context.candidate_page_first = 0
let s:lib.context.candidate_page_last = 0
let s:lib.context.candidate_page_size = 0

function s:lib.context.new(method, lang)
  let cx = deepcopy(self)
  let cx.method = a:method
  let cx.lang = a:lang
  let cx.status_label = a:method
  let lis = self.api.create_context(a:method, a:lang)
  call cx.event_loop(lis)
  return cx
endfunction

function s:lib.context.delete()
  call self.api.delete_context(self.handle)
endfunction

function s:lib.context.input(key, ...)
  let interactive = get(a:000, 0, 1)

  if has_key(self.kmap, a:key)
    let code = self.kmap[a:key].code
    let mod = self.kmap[a:key].mod
    let raw = self.kmap[a:key].raw

    let lis = self.api.send_key(self.handle, code, mod, raw)
    let res = self.event_loop(lis)
  else
    let res = ""
  endif

  call s:win.clear()
  if empty(self.preedit) && empty(self.candidate)
    call s:win.close()
  else
    call s:win.open()
    if mode() == "c"
      let s:cx = self
      return printf("%s\<C-R>=imbase#cmdline_loop()\<CR>", res)
    endif
    call s:win.print(self)
  endif

  if mode() == "n" && res == "" && !interactive
    " loop for fFtTr command
    redrawstatus
    let c = getchar()
    if type(c) == 0
      let c = nr2char(c)
    endif
    let res = self.input(c, 0)
  endif

  return res
endfunction

function imbase#cmdline_loop()
  " To keep preedit visible.
  " This does not work in <C-R>= inputting...
  " feedkeys() can not be used in <expr> mapping.
  call s:win.print(s:cx)
  let c = getchar()
  if type(c) == 0
    let c = nr2char(c)
  endif
  call feedkeys(c, "t")
  return ""
endfunction

"-----------------------------------------------------------
" Preedit/Candidate Window
let s:win = {}

function s:win.clear()
  let self.output = []
  let self.height = 1
  let self.curline_width = 0

  " avoid redraw problem when no preedit and no return.
  let sc_save = &showcmd
  let ru_save = &ruler
  set noshowcmd noruler
  echo ""
  let &ruler = ru_save
  let &showcmd = sc_save
endfunction

function s:win.echo_attr(str, attr)
  if a:attr == ""
    let hl = "gui=NONE cterm=NONE term=NONE"
  else
    let hl = printf("gui=%s cterm=%s term=%s", a:attr, a:attr, a:attr)
  endif
  hi clear _IMHL
  execute "hi _IMHL " . hl
  echohl _IMHL
  echon a:str
  echohl None
endfunction

function s:win.put_str(str, attr)
  for c in split(a:str, '\zs')
    if c == "\n"
      let self.height += 1
      let self.curline_width = 0
    else
      let self.curline_width += len(c) == 1 ? 1 : 2
      if self.curline_width >= &columns
        let self.height += 1
        let self.curline_width -= &columns
      endif
    endif
  endfor
  call add(self.output, [a:str, a:attr])
endfunction

function s:win.print(cx)
  let name = a:cx.method
  let preedit = a:cx.preedit
  let candidate = a:cx.candidate
  let candidate_current = a:cx.candidate_current
  let page_first = a:cx.candidate_page_first
  let page_last = a:cx.candidate_page_last

  call self.clear()

  if mode() == "c"
    call self.put_str(getcmdtype(), "")
    call self.put_str(strpart(getcmdline(), 0, getcmdpos()-1), "")
  else
    call self.put_str(name, "")
    call self.put_str(": ", "")
  endif

  if !empty(preedit)
    for [str, attr] in preedit
      call self.put_str(str, attr)
    endfor
  endif

  if mode() == "c"
    call self.put_str(strpart(getcmdline(), getcmdpos() - 1), "")
  endif

  if !empty(candidate)
    call self.put_str("\n", "")
    for i in range(page_first, page_last)
      let [label, str; _] = candidate[i]
      call self.put_str(label, "")
      if i == candidate_current
        call self.put_str(str, "reverse")
      else
        call self.put_str(str, "")
      endif
      call self.put_str(" ", "")
    endfor
    call self.put_str(printf("%d/%d", candidate_current + 1, len(candidate)), "")
  endif

  call self.resize()

  " reset 'showcmd' and 'ruler' to avoid "Press ENTER or type command to continue" prompt.
  let sc_save = &showcmd
  let ru_save = &ruler
  set noshowcmd noruler
  for [str, attr] in self.output
    call self.echo_attr(str, attr)
  endfor
  let &ruler = ru_save
  let &showcmd = sc_save
endfunction

function s:win.open()
  if !exists("s:smd_save")
    let s:smd_save = &showmode
    let s:ch_save = &cmdheight
    set noshowmode
  endif
endfunction

function s:win.close()
  if exists("s:smd_save")
    let &showmode = s:smd_save
    unlet s:smd_save
  endif
  if exists("s:ch_save")
    let &cmdheight = s:ch_save
    unlet s:ch_save
    if mode() == "c"
      redrawstatus
    endif
  endif
endfunction

function s:win.resize()
  if &cmdheight < self.height
    let &cmdheight = self.height
    if mode() == "c" || mode() == "n"
      redrawstatus
    endif
  endif
endfunction

let &cpo = s:cpo_save

