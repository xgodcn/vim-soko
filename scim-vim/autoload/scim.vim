" 2007-02-12

scriptencoding utf-8

let s:cpo_save = &cpo
set cpo&vim

function scim#import()
  return s:lib
endfunction

function scim#info()
  call s:lib.init()
  for [method, langs, desc, is_default] in s:lib.get_imlist()
    echo printf("%s (%s) %s", method, join(langs, ', '), is_default ? "*default*" : "")
  endfor
endfunction

function scim#select()
  call s:lib.init()
  let imlist = s:lib.get_imlist()
  let textlist = []
  let n = 1
  for [method, langs, desc, is_default] in imlist
    call add(textlist, printf("%d. %s (%s) %s", n, method, join(langs, ', '), is_default ? "*default*" : ""))
    let n += 1
  endfor
  let n = inputlist(textlist)
  if 0 < n && n <= len(imlist)
    let b:scim_method = imlist[n - 1][0]
    let b:scim_lang   = imlist[n - 1][1][0]
    setlocal keymap=scim
  endif
endfunction

augroup Scim
  autocmd VimLeave * call s:lib.uninit()
augroup END

let s:lib = deepcopy(imbase#import())

"-----------------------------------------------------------
" LOW LEVEL API
let s:lib.api.dll = expand("<sfile>:p:h") . "/scim-vim.so"

"-----------------------------------------------------------
" Input Method Context
let s:lib.context.api = s:lib.api
let s:lib.context.kmap = s:lib.kmap
let s:lib.context.property = []

function s:lib.context.event_loop(lis)
  let res = ""
  let lis = a:lis
  while !empty(lis)
    let [event] = remove(lis, 0, 0)

    if event == "create_context"
      let [handle] = remove(lis, 0, 0)
      let self.handle = handle

    elseif event == "commit_raw"
      let [raw] = remove(lis, 0, 0)
      let res .= s:lib.api.hex2str(raw)

    elseif event == "commit"
      let [str] = remove(lis, 0, 0)
      let res .= str

    elseif event == "show_preedit"

    elseif event == "show_candidate"

    elseif event == "hide_preedit"
      let self.preedit = []

    elseif event == "hide_candidate"
      let self.candidate = []

    elseif event == "update_preedit"
      let [varname, str, attrlen] = remove(lis, 0, 2)
      let attrs = (attrlen == 0) ? [] : remove(lis, 0, attrlen * 4 - 1)
      let self.preedit = s:parse_attr(str, attrs)

    elseif event == "update_candidate"
      let [varname, nr] = remove(lis, 0, 1)
      let candidate = []
      for i in range(nr)
        let [str] = remove(lis, 0, 0)
        call add(candidate, ["", str])
      endfor

      let [varname, nr] = remove(lis, 0, 1)
      let page = []
      for i in range(nr)
        let [label, str, attrlen] = remove(lis, 0, 2)
        let attrs = (attrlen == 0) ? [] : remove(lis, 0, attrlen * 4 - 1)
        call add(page, [label, s:parse_attr(str, attrs)])
      endfor

      let [current, first, last] = remove(lis, 0, 2)

      for i in range(nr)
        let candidate[i + first][0] = page[i][0]
      endfor

      let self.candidate = candidate
      let self.candidate_current = current
      let self.candidate_page_first = first
      let self.candidate_page_last = last

    elseif event == "register_property" || event == "property"
      let [key, label, icon, tip, visible, active] = remove(lis, 0, 5)
      let item = {}
      let item.key = key
      let item.val = {}
      let item.val["label"] = label
      let item.val["icon"] = icon
      let item.val["tip"] = tip
      let item.val["visible"] = visible
      let item.val["active"] = active
      let n = -1
      for i in range(len(self.property))
        if self.property[i].key == key
          let n = i
          break
        endif
      endfor
      if n != -1
        let self.property[i] = item
      else
        call add(self.property, item)
      endif

      " Branch   /IMEngine/<im-name>/<prop-name>
      " Leaf     /IMEngine/<im-name>/<prop-name>/<leaf>
      let self.status_label = self.method . ":"
      for item in self.property
        if item.key =~ '^/[^/]\+/[^/]\+/[^/]*[^/]$' && item.val["label"] != ""
          let self.status_label .= "[" . item.val["label"] . "]"
        endif
      endfor

    else
      echoerr "Assertion: Unknown event " event
    endif
  endwhile
  return res
endfunction

function s:parse_attr(str, attrs)
  let SCIM_ATTR_NONE = 0
  let SCIM_ATTR_DECORATE = 1
  let SCIM_ATTR_FOREGROUND = 2
  let SCIM_ATTR_BACKGROUND = 3
  let res = map(split(a:str, '\zs'), '[v:val, ""]')
  let attrs = a:attrs
  while !empty(attrs)
    let [type, value, start, end; attrs] = attrs
    for i in range(start, end - 1)
      if type == SCIM_ATTR_NONE
        " pass
      elseif type == SCIM_ATTR_DECORATE
        let attr = []
        if value % 2 != 0
          call add(attr, "underline")
        endif
        if (value / 2) % 2 != 0   " Draw the text in highlighted color
          " pass
        endif
        if (value / 4) % 2 != 0
          call add(attr, "reverse")
        endif
        let res[i][1] = join(attr, ",")
      elseif type == SCIM_ATTR_FOREGROUND
        " pass
      elseif type == SCIM_ATTR_BACKGROUND
        " pass
      else
        echoerr "Assertion: Unknown Attribute Type " type
      endif
    endfor
  endwhile
  return res
endfunction


"-----------------------------------------------------------
" Key mapping.
let s:lib.kmod.shift = 1
let s:lib.kmod.ctrl = 4
let s:lib.kmod.alt = 8

let s:lib.kmap["\<C-A>"] = {"map":"<C-A>", "code":0x41, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-B>"] = {"map":"<C-B>", "code":0x42, "mod":s:lib.kmod.ctrl}
" It is not useful to override <C-C>
" let s:lib.kmap["\<C-C>"] = {"map":"<C-C>", "code":0x43, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-D>"] = {"map":"<C-D>", "code":0x44, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-E>"] = {"map":"<C-E>", "code":0x45, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F>"] = {"map":"<C-F>", "code":0x46, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-G>"] = {"map":"<C-G>", "code":0x47, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-H>"] = {"map":"<C-H>", "code":0x48, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-I>"] = {"map":"<C-I>", "code":0x49, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-J>"] = {"map":"<C-J>", "code":0x4a, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-K>"] = {"map":"<C-K>", "code":0x4b, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-L>"] = {"map":"<C-L>", "code":0x4c, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-M>"] = {"map":"<C-M>", "code":0x4d, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-N>"] = {"map":"<C-N>", "code":0x4e, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-O>"] = {"map":"<C-O>", "code":0x4f, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-P>"] = {"map":"<C-P>", "code":0x50, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Q>"] = {"map":"<C-Q>", "code":0x51, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-R>"] = {"map":"<C-R>", "code":0x52, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-S>"] = {"map":"<C-S>", "code":0x53, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-T>"] = {"map":"<C-T>", "code":0x54, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-U>"] = {"map":"<C-U>", "code":0x55, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-V>"] = {"map":"<C-V>", "code":0x56, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-W>"] = {"map":"<C-W>", "code":0x57, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-X>"] = {"map":"<C-X>", "code":0x58, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Y>"] = {"map":"<C-Y>", "code":0x59, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Z>"] = {"map":"<C-Z>", "code":0x5a, "mod":s:lib.kmod.ctrl}
" Vim cannot distinguish <C-[> and <Esc>.  Use <Esc>.
" let s:lib.kmap["\<C-[>"] = {"map":"<C-[>", "code":0x5b, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-[>"] = {"map":"<C-[>", "code":0xFF1B, "mod":0}
let s:lib.kmap["\<C-\>"] = {"map":'<C-\>', "code":0x5c, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-]>"] = {"map":"<C-]>", "code":0x5d, "mod":s:lib.kmod.ctrl}
" this causes redraw problem when turn off langmap on cmdline.
" let s:lib.kmap["\<C-^>"] = {"map":"<C-^>", "code":0x5e, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-_>"] = {"map":"<C-_>", "code":0x5f, "mod":s:lib.kmod.ctrl}
let s:lib.kmap[" "] = {"map":"<Space>", "code":0x20, "mod":0}
let s:lib.kmap["!"] = {"map":"!", "code":0x21, "mod":0}
let s:lib.kmap['"'] = {"map":'"', "code":0x22, "mod":0}
let s:lib.kmap["#"] = {"map":"#", "code":0x23, "mod":0}
let s:lib.kmap["$"] = {"map":"$", "code":0x24, "mod":0}
let s:lib.kmap["%"] = {"map":"%", "code":0x25, "mod":0}
let s:lib.kmap["&"] = {"map":"&", "code":0x26, "mod":0}
let s:lib.kmap["'"] = {"map":"'", "code":0x27, "mod":0}
let s:lib.kmap["("] = {"map":"(", "code":0x28, "mod":0}
let s:lib.kmap[")"] = {"map":")", "code":0x29, "mod":0}
let s:lib.kmap["*"] = {"map":"*", "code":0x2a, "mod":0}
let s:lib.kmap["+"] = {"map":"+", "code":0x2b, "mod":0}
let s:lib.kmap[","] = {"map":",", "code":0x2c, "mod":0}
let s:lib.kmap["-"] = {"map":"-", "code":0x2d, "mod":0}
let s:lib.kmap["."] = {"map":".", "code":0x2e, "mod":0}
let s:lib.kmap["/"] = {"map":"/", "code":0x2f, "mod":0}
let s:lib.kmap["0"] = {"map":"0", "code":0x30, "mod":0}
let s:lib.kmap["1"] = {"map":"1", "code":0x31, "mod":0}
let s:lib.kmap["2"] = {"map":"2", "code":0x32, "mod":0}
let s:lib.kmap["3"] = {"map":"3", "code":0x33, "mod":0}
let s:lib.kmap["4"] = {"map":"4", "code":0x34, "mod":0}
let s:lib.kmap["5"] = {"map":"5", "code":0x35, "mod":0}
let s:lib.kmap["6"] = {"map":"6", "code":0x36, "mod":0}
let s:lib.kmap["7"] = {"map":"7", "code":0x37, "mod":0}
let s:lib.kmap["8"] = {"map":"8", "code":0x38, "mod":0}
let s:lib.kmap["9"] = {"map":"9", "code":0x39, "mod":0}
let s:lib.kmap[":"] = {"map":":", "code":0x3a, "mod":0}
let s:lib.kmap[";"] = {"map":";", "code":0x3b, "mod":0}
let s:lib.kmap["<"] = {"map":"<", "code":0x3c, "mod":0}
let s:lib.kmap["="] = {"map":"=", "code":0x3d, "mod":0}
let s:lib.kmap[">"] = {"map":">", "code":0x3e, "mod":0}
let s:lib.kmap["?"] = {"map":"?", "code":0x3f, "mod":0}
let s:lib.kmap["@"] = {"map":"@", "code":0x40, "mod":0}
let s:lib.kmap["A"] = {"map":"A", "code":0x41, "mod":s:lib.kmod.shift}
let s:lib.kmap["B"] = {"map":"B", "code":0x42, "mod":s:lib.kmod.shift}
let s:lib.kmap["C"] = {"map":"C", "code":0x43, "mod":s:lib.kmod.shift}
let s:lib.kmap["D"] = {"map":"D", "code":0x44, "mod":s:lib.kmod.shift}
let s:lib.kmap["E"] = {"map":"E", "code":0x45, "mod":s:lib.kmod.shift}
let s:lib.kmap["F"] = {"map":"F", "code":0x46, "mod":s:lib.kmod.shift}
let s:lib.kmap["G"] = {"map":"G", "code":0x47, "mod":s:lib.kmod.shift}
let s:lib.kmap["H"] = {"map":"H", "code":0x48, "mod":s:lib.kmod.shift}
let s:lib.kmap["I"] = {"map":"I", "code":0x49, "mod":s:lib.kmod.shift}
let s:lib.kmap["J"] = {"map":"J", "code":0x4a, "mod":s:lib.kmod.shift}
let s:lib.kmap["K"] = {"map":"K", "code":0x4b, "mod":s:lib.kmod.shift}
let s:lib.kmap["L"] = {"map":"L", "code":0x4c, "mod":s:lib.kmod.shift}
let s:lib.kmap["M"] = {"map":"M", "code":0x4d, "mod":s:lib.kmod.shift}
let s:lib.kmap["N"] = {"map":"N", "code":0x4e, "mod":s:lib.kmod.shift}
let s:lib.kmap["O"] = {"map":"O", "code":0x4f, "mod":s:lib.kmod.shift}
let s:lib.kmap["P"] = {"map":"P", "code":0x50, "mod":s:lib.kmod.shift}
let s:lib.kmap["Q"] = {"map":"Q", "code":0x51, "mod":s:lib.kmod.shift}
let s:lib.kmap["R"] = {"map":"R", "code":0x52, "mod":s:lib.kmod.shift}
let s:lib.kmap["S"] = {"map":"S", "code":0x53, "mod":s:lib.kmod.shift}
let s:lib.kmap["T"] = {"map":"T", "code":0x54, "mod":s:lib.kmod.shift}
let s:lib.kmap["U"] = {"map":"U", "code":0x55, "mod":s:lib.kmod.shift}
let s:lib.kmap["V"] = {"map":"V", "code":0x56, "mod":s:lib.kmod.shift}
let s:lib.kmap["W"] = {"map":"W", "code":0x57, "mod":s:lib.kmod.shift}
let s:lib.kmap["X"] = {"map":"X", "code":0x58, "mod":s:lib.kmod.shift}
let s:lib.kmap["Y"] = {"map":"Y", "code":0x59, "mod":s:lib.kmod.shift}
let s:lib.kmap["Z"] = {"map":"Z", "code":0x5a, "mod":s:lib.kmod.shift}
let s:lib.kmap["["] = {"map":"[", "code":0x5b, "mod":0}
let s:lib.kmap['\'] = {"map":"<BSlash>", "code":0x5c, "mod":0}
let s:lib.kmap["]"] = {"map":"]", "code":0x5d, "mod":0}
let s:lib.kmap["^"] = {"map":"^", "code":0x5e, "mod":0}
let s:lib.kmap["_"] = {"map":"_", "code":0x5f, "mod":0}
let s:lib.kmap["`"] = {"map":"`", "code":0x60, "mod":0}
let s:lib.kmap["a"] = {"map":"a", "code":0x61, "mod":0}
let s:lib.kmap["b"] = {"map":"b", "code":0x62, "mod":0}
let s:lib.kmap["c"] = {"map":"c", "code":0x63, "mod":0}
let s:lib.kmap["d"] = {"map":"d", "code":0x64, "mod":0}
let s:lib.kmap["e"] = {"map":"e", "code":0x65, "mod":0}
let s:lib.kmap["f"] = {"map":"f", "code":0x66, "mod":0}
let s:lib.kmap["g"] = {"map":"g", "code":0x67, "mod":0}
let s:lib.kmap["h"] = {"map":"h", "code":0x68, "mod":0}
let s:lib.kmap["i"] = {"map":"i", "code":0x69, "mod":0}
let s:lib.kmap["j"] = {"map":"j", "code":0x6a, "mod":0}
let s:lib.kmap["k"] = {"map":"k", "code":0x6b, "mod":0}
let s:lib.kmap["l"] = {"map":"l", "code":0x6c, "mod":0}
let s:lib.kmap["m"] = {"map":"m", "code":0x6d, "mod":0}
let s:lib.kmap["n"] = {"map":"n", "code":0x6e, "mod":0}
let s:lib.kmap["o"] = {"map":"o", "code":0x6f, "mod":0}
let s:lib.kmap["p"] = {"map":"p", "code":0x70, "mod":0}
let s:lib.kmap["q"] = {"map":"q", "code":0x71, "mod":0}
let s:lib.kmap["r"] = {"map":"r", "code":0x72, "mod":0}
let s:lib.kmap["s"] = {"map":"s", "code":0x73, "mod":0}
let s:lib.kmap["t"] = {"map":"t", "code":0x74, "mod":0}
let s:lib.kmap["u"] = {"map":"u", "code":0x75, "mod":0}
let s:lib.kmap["v"] = {"map":"v", "code":0x76, "mod":0}
let s:lib.kmap["w"] = {"map":"w", "code":0x77, "mod":0}
let s:lib.kmap["x"] = {"map":"x", "code":0x78, "mod":0}
let s:lib.kmap["y"] = {"map":"y", "code":0x79, "mod":0}
let s:lib.kmap["z"] = {"map":"z", "code":0x7a, "mod":0}
let s:lib.kmap["{"] = {"map":"{", "code":0x7b, "mod":0}
let s:lib.kmap["|"] = {"map":"<Bar>", "code":0x7c, "mod":0}
let s:lib.kmap["}"] = {"map":"}", "code":0x7d, "mod":0}
let s:lib.kmap["~"] = {"map":"~", "code":0x7e, "mod":0}

" Since <Tab> and <C-I> has same key code, use <S-Tab> for <Tab>.
let s:lib.kmap["\<S-Tab>"] = {"map":"<S-Tab>", "code":0xFF09, "mod":0}
let s:lib.kmap["\<BS>"] = {"map":"<BS>", "code":0xFF08, "mod":0}
let s:lib.kmap["\<Del>"] = {"map":"<Del>", "code":0xFFFF, "mod":0}
let s:lib.kmap["\<CR>"] = {"map":"<CR>", "code":0xFF0D, "mod":0}
let s:lib.kmap["\<Left>"] = {"map":"<Left>", "code":0xFF51, "mod":0}
let s:lib.kmap["\<Up>"] = {"map":"<Up>", "code":0xFF52, "mod":0}
let s:lib.kmap["\<Right>"] = {"map":"<Right>", "code":0xFF53, "mod":0}
let s:lib.kmap["\<Down>"] = {"map":"<Down>", "code":0xFF54, "mod":0}
let s:lib.kmap["\<PageUp>"] = {"map":"<PageUp>", "code":0xFF55, "mod":0}
let s:lib.kmap["\<PageDown>"] = {"map":"<PageDown>", "code":0xFF56, "mod":0}
let s:lib.kmap["\<Home>"] = {"map":"<Home>", "code":0xFF50, "mod":0}
let s:lib.kmap["\<End>"] = {"map":"<End>", "code":0xFF57, "mod":0}
let s:lib.kmap["\<F1>"] = {"map":"<F1>", "code":0xFFBE, "mod":0}
let s:lib.kmap["\<F2>"] = {"map":"<F2>", "code":0xFFBF, "mod":0}
let s:lib.kmap["\<F3>"] = {"map":"<F3>", "code":0xFFC0, "mod":0}
let s:lib.kmap["\<F4>"] = {"map":"<F4>", "code":0xFFC1, "mod":0}
let s:lib.kmap["\<F5>"] = {"map":"<F5>", "code":0xFFC2, "mod":0}
let s:lib.kmap["\<F6>"] = {"map":"<F6>", "code":0xFFC3, "mod":0}
let s:lib.kmap["\<F7>"] = {"map":"<F7>", "code":0xFFC4, "mod":0}
let s:lib.kmap["\<F8>"] = {"map":"<F8>", "code":0xFFC5, "mod":0}
let s:lib.kmap["\<F9>"] = {"map":"<F9>", "code":0xFFC6, "mod":0}
let s:lib.kmap["\<F10>"] = {"map":"<F10>", "code":0xFFC7, "mod":0}
let s:lib.kmap["\<F11>"] = {"map":"<F11>", "code":0xFFC8, "mod":0}
let s:lib.kmap["\<F12>"] = {"map":"<F12>", "code":0xFFC9, "mod":0}
let s:lib.kmap["\<F13>"] = {"map":"<F13>", "code":0xFFCA, "mod":0}
let s:lib.kmap["\<F14>"] = {"map":"<F14>", "code":0xFFCB, "mod":0}
let s:lib.kmap["\<F15>"] = {"map":"<F15>", "code":0xFFCC, "mod":0}
let s:lib.kmap["\<F16>"] = {"map":"<F16>", "code":0xFFCD, "mod":0}
let s:lib.kmap["\<F17>"] = {"map":"<F17>", "code":0xFFCE, "mod":0}
let s:lib.kmap["\<F18>"] = {"map":"<F18>", "code":0xFFCF, "mod":0}
let s:lib.kmap["\<F19>"] = {"map":"<F19>", "code":0xFFD0, "mod":0}
let s:lib.kmap["\<F20>"] = {"map":"<F20>", "code":0xFFD1, "mod":0}
let s:lib.kmap["\<F21>"] = {"map":"<F21>", "code":0xFFD2, "mod":0}
let s:lib.kmap["\<F22>"] = {"map":"<F22>", "code":0xFFD3, "mod":0}
let s:lib.kmap["\<F23>"] = {"map":"<F23>", "code":0xFFD4, "mod":0}
let s:lib.kmap["\<F24>"] = {"map":"<F24>", "code":0xFFD5, "mod":0}
let s:lib.kmap["\<F25>"] = {"map":"<F25>", "code":0xFFD6, "mod":0}
let s:lib.kmap["\<F26>"] = {"map":"<F26>", "code":0xFFD7, "mod":0}
let s:lib.kmap["\<F27>"] = {"map":"<F27>", "code":0xFFD8, "mod":0}
let s:lib.kmap["\<F28>"] = {"map":"<F28>", "code":0xFFD9, "mod":0}
let s:lib.kmap["\<F29>"] = {"map":"<F29>", "code":0xFFDA, "mod":0}
let s:lib.kmap["\<F30>"] = {"map":"<F30>", "code":0xFFDB, "mod":0}
let s:lib.kmap["\<F31>"] = {"map":"<F31>", "code":0xFFDC, "mod":0}
let s:lib.kmap["\<F32>"] = {"map":"<F32>", "code":0xFFDD, "mod":0}
let s:lib.kmap["\<F33>"] = {"map":"<F33>", "code":0xFFDE, "mod":0}
let s:lib.kmap["\<F34>"] = {"map":"<F34>", "code":0xFFDF, "mod":0}
let s:lib.kmap["\<F35>"] = {"map":"<F35>", "code":0xFFE0, "mod":0}

let s:lib.kmap["\<S-BS>"] = {"map":"<S-BS>", "code":0xFF08, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-Del>"] = {"map":"<S-Del>", "code":0xFFFF, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-CR>"] = {"map":"<S-CR>", "code":0xFF0D, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-Left>"] = {"map":"<S-Left>", "code":0xFF51, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-Up>"] = {"map":"<S-Up>", "code":0xFF52, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-Right>"] = {"map":"<S-Right>", "code":0xFF53, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-Down>"] = {"map":"<S-Down>", "code":0xFF54, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-PageUp>"] = {"map":"<S-PageUp>", "code":0xFF55, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-PageDown>"] = {"map":"<S-PageDown>", "code":0xFF56, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-Home>"] = {"map":"<S-Home>", "code":0xFF50, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-End>"] = {"map":"<S-End>", "code":0xFF57, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F1>"] = {"map":"<S-F1>", "code":0xFFBE, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F2>"] = {"map":"<S-F2>", "code":0xFFBF, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F3>"] = {"map":"<S-F3>", "code":0xFFC0, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F4>"] = {"map":"<S-F4>", "code":0xFFC1, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F5>"] = {"map":"<S-F5>", "code":0xFFC2, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F6>"] = {"map":"<S-F6>", "code":0xFFC3, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F7>"] = {"map":"<S-F7>", "code":0xFFC4, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F8>"] = {"map":"<S-F8>", "code":0xFFC5, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F9>"] = {"map":"<S-F9>", "code":0xFFC6, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F10>"] = {"map":"<S-F10>", "code":0xFFC7, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F11>"] = {"map":"<S-F11>", "code":0xFFC8, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F12>"] = {"map":"<S-F12>", "code":0xFFC9, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F13>"] = {"map":"<S-F13>", "code":0xFFCA, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F14>"] = {"map":"<S-F14>", "code":0xFFCB, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F15>"] = {"map":"<S-F15>", "code":0xFFCC, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F16>"] = {"map":"<S-F16>", "code":0xFFCD, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F17>"] = {"map":"<S-F17>", "code":0xFFCE, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F18>"] = {"map":"<S-F18>", "code":0xFFCF, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F19>"] = {"map":"<S-F19>", "code":0xFFD0, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F20>"] = {"map":"<S-F20>", "code":0xFFD1, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F21>"] = {"map":"<S-F21>", "code":0xFFD2, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F22>"] = {"map":"<S-F22>", "code":0xFFD3, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F23>"] = {"map":"<S-F23>", "code":0xFFD4, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F24>"] = {"map":"<S-F24>", "code":0xFFD5, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F25>"] = {"map":"<S-F25>", "code":0xFFD6, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F26>"] = {"map":"<S-F26>", "code":0xFFD7, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F27>"] = {"map":"<S-F27>", "code":0xFFD8, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F28>"] = {"map":"<S-F28>", "code":0xFFD9, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F29>"] = {"map":"<S-F29>", "code":0xFFDA, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F30>"] = {"map":"<S-F30>", "code":0xFFDB, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F31>"] = {"map":"<S-F31>", "code":0xFFDC, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F32>"] = {"map":"<S-F32>", "code":0xFFDD, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F33>"] = {"map":"<S-F33>", "code":0xFFDE, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F34>"] = {"map":"<S-F34>", "code":0xFFDF, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F35>"] = {"map":"<S-F35>", "code":0xFFE0, "mod":s:lib.kmod.shift}

let s:lib.kmap["\<C-BS>"] = {"map":"<C-BS>", "code":0xFF08, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Del>"] = {"map":"<C-Del>", "code":0xFFFF, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-CR>"] = {"map":"<C-CR>", "code":0xFF0D, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Left>"] = {"map":"<C-Left>", "code":0xFF51, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Up>"] = {"map":"<C-Up>", "code":0xFF52, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Right>"] = {"map":"<C-Right>", "code":0xFF53, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Down>"] = {"map":"<C-Down>", "code":0xFF54, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-PageUp>"] = {"map":"<C-PageUp>", "code":0xFF55, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-PageDown>"] = {"map":"<C-PageDown>", "code":0xFF56, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Home>"] = {"map":"<C-Home>", "code":0xFF50, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-End>"] = {"map":"<C-End>", "code":0xFF57, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F1>"] = {"map":"<C-F1>", "code":0xFFBE, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F2>"] = {"map":"<C-F2>", "code":0xFFBF, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F3>"] = {"map":"<C-F3>", "code":0xFFC0, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F4>"] = {"map":"<C-F4>", "code":0xFFC1, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F5>"] = {"map":"<C-F5>", "code":0xFFC2, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F6>"] = {"map":"<C-F6>", "code":0xFFC3, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F7>"] = {"map":"<C-F7>", "code":0xFFC4, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F8>"] = {"map":"<C-F8>", "code":0xFFC5, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F9>"] = {"map":"<C-F9>", "code":0xFFC6, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F10>"] = {"map":"<C-F10>", "code":0xFFC7, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F11>"] = {"map":"<C-F11>", "code":0xFFC8, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F12>"] = {"map":"<C-F12>", "code":0xFFC9, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F13>"] = {"map":"<C-F13>", "code":0xFFCA, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F14>"] = {"map":"<C-F14>", "code":0xFFCB, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F15>"] = {"map":"<C-F15>", "code":0xFFCC, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F16>"] = {"map":"<C-F16>", "code":0xFFCD, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F17>"] = {"map":"<C-F17>", "code":0xFFCE, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F18>"] = {"map":"<C-F18>", "code":0xFFCF, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F19>"] = {"map":"<C-F19>", "code":0xFFD0, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F20>"] = {"map":"<C-F20>", "code":0xFFD1, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F21>"] = {"map":"<C-F21>", "code":0xFFD2, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F22>"] = {"map":"<C-F22>", "code":0xFFD3, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F23>"] = {"map":"<C-F23>", "code":0xFFD4, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F24>"] = {"map":"<C-F24>", "code":0xFFD5, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F25>"] = {"map":"<C-F25>", "code":0xFFD6, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F26>"] = {"map":"<C-F26>", "code":0xFFD7, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F27>"] = {"map":"<C-F27>", "code":0xFFD8, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F28>"] = {"map":"<C-F28>", "code":0xFFD9, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F29>"] = {"map":"<C-F29>", "code":0xFFDA, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F30>"] = {"map":"<C-F30>", "code":0xFFDB, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F31>"] = {"map":"<C-F31>", "code":0xFFDC, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F32>"] = {"map":"<C-F32>", "code":0xFFDD, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F33>"] = {"map":"<C-F33>", "code":0xFFDE, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F34>"] = {"map":"<C-F34>", "code":0xFFDF, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F35>"] = {"map":"<C-F35>", "code":0xFFE0, "mod":s:lib.kmod.ctrl}

let s:lib.kmap["\<S-C-BS>"] = {"map":"<S-C-BS>", "code":0xFF08, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-Del>"] = {"map":"<S-C-Del>", "code":0xFFFF, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-CR>"] = {"map":"<S-C-CR>", "code":0xFF0D, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-Left>"] = {"map":"<S-C-Left>", "code":0xFF51, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-Up>"] = {"map":"<S-C-Up>", "code":0xFF52, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-Right>"] = {"map":"<S-C-Right>", "code":0xFF53, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-Down>"] = {"map":"<S-C-Down>", "code":0xFF54, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-PageUp>"] = {"map":"<S-C-PageUp>", "code":0xFF55, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-PageDown>"] = {"map":"<S-C-PageDown>", "code":0xFF56, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-Home>"] = {"map":"<S-C-Home>", "code":0xFF50, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-End>"] = {"map":"<S-C-End>", "code":0xFF57, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F1>"] = {"map":"<S-C-F1>", "code":0xFFBE, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F2>"] = {"map":"<S-C-F2>", "code":0xFFBF, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F3>"] = {"map":"<S-C-F3>", "code":0xFFC0, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F4>"] = {"map":"<S-C-F4>", "code":0xFFC1, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F5>"] = {"map":"<S-C-F5>", "code":0xFFC2, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F6>"] = {"map":"<S-C-F6>", "code":0xFFC3, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F7>"] = {"map":"<S-C-F7>", "code":0xFFC4, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F8>"] = {"map":"<S-C-F8>", "code":0xFFC5, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F9>"] = {"map":"<S-C-F9>", "code":0xFFC6, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F10>"] = {"map":"<S-C-F10>", "code":0xFFC7, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F11>"] = {"map":"<S-C-F11>", "code":0xFFC8, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F12>"] = {"map":"<S-C-F12>", "code":0xFFC9, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F13>"] = {"map":"<S-C-F13>", "code":0xFFCA, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F14>"] = {"map":"<S-C-F14>", "code":0xFFCB, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F15>"] = {"map":"<S-C-F15>", "code":0xFFCC, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F16>"] = {"map":"<S-C-F16>", "code":0xFFCD, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F17>"] = {"map":"<S-C-F17>", "code":0xFFCE, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F18>"] = {"map":"<S-C-F18>", "code":0xFFCF, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F19>"] = {"map":"<S-C-F19>", "code":0xFFD0, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F20>"] = {"map":"<S-C-F20>", "code":0xFFD1, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F21>"] = {"map":"<S-C-F21>", "code":0xFFD2, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F22>"] = {"map":"<S-C-F22>", "code":0xFFD3, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F23>"] = {"map":"<S-C-F23>", "code":0xFFD4, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F24>"] = {"map":"<S-C-F24>", "code":0xFFD5, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F25>"] = {"map":"<S-C-F25>", "code":0xFFD6, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F26>"] = {"map":"<S-C-F26>", "code":0xFFD7, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F27>"] = {"map":"<S-C-F27>", "code":0xFFD8, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F28>"] = {"map":"<S-C-F28>", "code":0xFFD9, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F29>"] = {"map":"<S-C-F29>", "code":0xFFDA, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F30>"] = {"map":"<S-C-F30>", "code":0xFFDB, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F31>"] = {"map":"<S-C-F31>", "code":0xFFDC, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F32>"] = {"map":"<S-C-F32>", "code":0xFFDD, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F33>"] = {"map":"<S-C-F33>", "code":0xFFDE, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F34>"] = {"map":"<S-C-F34>", "code":0xFFDF, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F35>"] = {"map":"<S-C-F35>", "code":0xFFE0, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}

let s:lib.kmap["<Zenkaku_Hankaku>"] = {"map":"", "code":0xFF2A, "mod":0}
let s:lib.kmap["<C-,>"] = {"map":"", "code":0x2c, "mod":s:lib.kmod.ctrl}

" Set "raw" for raw commit.
" Do not use control code directory.  When 'encoding' is not utf-8 it is
" converted from utf-8 to &encoding with iconv() and it should become invalid
" (like "??x").
for [s:k, s:v] in items(s:lib.kmap)
  if s:k ==# "\<S-Tab>"
    let s:v.raw = s:lib.api.str2hex("\<Tab>")
  else
    let s:v.raw = s:lib.api.str2hex(s:k)
  endif
endfor
unlet s:k s:v

let &cpo = s:cpo_save

