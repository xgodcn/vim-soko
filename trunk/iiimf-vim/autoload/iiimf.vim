" 2007-03-12

scriptencoding utf-8

let s:cpo_save = &cpo
set cpo&vim

function iiimf#import()
  return s:lib
endfunction

function iiimf#info()
  call s:lib.init()
  for [method, langs, desc, is_default] in s:lib.get_imlist()
    echo printf("%s (%s) %s", method, join(langs, ', '), is_default ? "*default*" : "")
  endfor
endfunction

function iiimf#select()
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
    let b:iiimf_method = imlist[n - 1][0]
    let b:iiimf_lang   = imlist[n - 1][1][0]
    setlocal keymap=iiimf
  endif
endfunction

augroup Iiimf
  autocmd VimLeave * call s:lib.uninit()
augroup END

let s:lib = deepcopy(imbase#import())

"-----------------------------------------------------------
" LOW LEVEL API
let s:lib.api.dll = expand("<sfile>:p:h") . "/iiimf-vim.so"

function! s:lib.api.uninit()
  if has("gui_running") && $GTK_IM_MODULE == "iiim"
    " Don't invoke iiimcf_finalize() yet because iiimf-vim and iiim
    " gtk_im_module are running in same process.
    return self.libcall("uninit", [0])
  endif
  return self.libcall("uninit", [1])
endfunction

"-----------------------------------------------------------
" Input Method Context
let s:lib.context.api = s:lib.api
let s:lib.context.kmap = s:lib.kmap

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

    elseif event == "preedit_clear"
      let self.preedit = []

    elseif event == "preedit_pushback"
      let [str, pos] = remove(lis, 0, 1)
      " Check if string is empty. It is passed from some IM.
      " Maybe it is aim of keeping preedit window?
      let attr = ""
      let self.preedit = []
      if str != ""
        call add(self.preedit, [str, attr])
      endif

    elseif event == "candidate_activate"
      let [varname, first, last, current, len] = remove(lis, 0, 4)
      let candidate = []
      for i in range(len)
        let [label, str] = remove(lis, 0, 1)
        call add(candidate, [label, str])
      endfor
      let self.candidate = candidate
      let self.candidate_current = current
      let self.candidate_page_first = first
      let self.candidate_page_last = last

    elseif event == "candidate_deactivate"
      let self.candidate = []

    elseif event == "status"
      let [status] = remove(lis, 0, 0)
      let self.status = status
      let self.status_label = printf("%s:%s", self.method, status)

    else
      echoerr "Assertion: Unknown event " event
    endif
  endwhile
  return res
endfunction


"-----------------------------------------------------------
" Key mapping.
let s:lib.kmod.shift = 16
let s:lib.kmod.ctrl = 17
let s:lib.kmod.alt = 18

let s:lib.kmap["\<C-A>"] = {"map":"<C-A>", "code":65, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-B>"] = {"map":"<C-B>", "code":66, "mod":s:lib.kmod.ctrl}
" It is not useful to override <C-C>
" let s:lib.kmap["\<C-C>"] = {"map":"<C-C>", "code":67, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-D>"] = {"map":"<C-D>", "code":68, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-E>"] = {"map":"<C-E>", "code":69, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F>"] = {"map":"<C-F>", "code":70, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-G>"] = {"map":"<C-F>", "code":71, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-H>"] = {"map":"<C-H>", "code":72, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-I>"] = {"map":"<C-I>", "code":73, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-J>"] = {"map":"<C-J>", "code":74, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-K>"] = {"map":"<C-K>", "code":75, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-L>"] = {"map":"<C-L>", "code":76, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-M>"] = {"map":"<C-M>", "code":77, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-N>"] = {"map":"<C-N>", "code":78, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-O>"] = {"map":"<C-O>", "code":79, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-P>"] = {"map":"<C-P>", "code":80, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Q>"] = {"map":"<C-Q>", "code":81, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-R>"] = {"map":"<C-R>", "code":82, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-S>"] = {"map":"<C-S>", "code":83, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-T>"] = {"map":"<C-T>", "code":84, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-U>"] = {"map":"<C-U>", "code":85, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-V>"] = {"map":"<C-V>", "code":86, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-W>"] = {"map":"<C-W>", "code":87, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-X>"] = {"map":"<C-X>", "code":88, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Y>"] = {"map":"<C-Y>", "code":89, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Z>"] = {"map":"<C-Z>", "code":90, "mod":s:lib.kmod.ctrl}
" Vim cannot distinguish <C-[> and <Esc>.  Use <Esc>.
" let s:lib.kmap["\<C-[>"] = {"map":"<C-[>", "code":91, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-[>"] = {"map":"<C-[>", "code":27, "mod":0}
let s:lib.kmap["\<C-\>"] = {"map":'<C-\>', "code":92, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-]>"] = {"map":"<C-]>", "code":93, "mod":s:lib.kmod.ctrl}
" this causes redraw problem when turn off langmap on cmdline.
" let s:lib.kmap["\<C-^>"] = {"map":"<C-^>", "code":514, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-_>"] = {"map":"<C-_>", "code":523, "mod":s:lib.kmod.ctrl}
let s:lib.kmap[" "] = {"map":"<Space>", "code":32, "mod":0}
let s:lib.kmap["!"] = {"map":"!", "code":517, "mod":0}
let s:lib.kmap['"'] = {"map":'"', "code":152, "mod":0}
let s:lib.kmap["#"] = {"map":"#", "code":520, "mod":0}
let s:lib.kmap["$"] = {"map":"$", "code":515, "mod":0}
let s:lib.kmap["%"] = {"map":"%", "code":53, "mod":s:lib.kmod.shift}
let s:lib.kmap["&"] = {"map":"&", "code":151, "mod":0}
let s:lib.kmap["'"] = {"map":"'", "code":222, "mod":0}
let s:lib.kmap["("] = {"map":"(", "code":519, "mod":0}
let s:lib.kmap[")"] = {"map":")", "code":522, "mod":0}
let s:lib.kmap["*"] = {"map":"*", "code":151, "mod":0}
let s:lib.kmap["+"] = {"map":"+", "code":521, "mod":0}
let s:lib.kmap[","] = {"map":",", "code":44, "mod":0}
let s:lib.kmap["-"] = {"map":"-", "code":45, "mod":0}
let s:lib.kmap["."] = {"map":".", "code":46, "mod":0}
let s:lib.kmap["/"] = {"map":"/", "code":47, "mod":0}
let s:lib.kmap["0"] = {"map":"0", "code":48, "mod":0}
let s:lib.kmap["1"] = {"map":"1", "code":49, "mod":0}
let s:lib.kmap["2"] = {"map":"2", "code":50, "mod":0}
let s:lib.kmap["3"] = {"map":"3", "code":51, "mod":0}
let s:lib.kmap["4"] = {"map":"4", "code":52, "mod":0}
let s:lib.kmap["5"] = {"map":"5", "code":53, "mod":0}
let s:lib.kmap["6"] = {"map":"6", "code":54, "mod":0}
let s:lib.kmap["7"] = {"map":"7", "code":55, "mod":0}
let s:lib.kmap["8"] = {"map":"8", "code":56, "mod":0}
let s:lib.kmap["9"] = {"map":"9", "code":57, "mod":0}
let s:lib.kmap[":"] = {"map":":", "code":513, "mod":0}
let s:lib.kmap[";"] = {"map":";", "code":59, "mod":0}
let s:lib.kmap["<"] = {"map":"<", "code":153, "mod":0}
let s:lib.kmap["="] = {"map":"=", "code":61, "mod":0}
let s:lib.kmap[">"] = {"map":">", "code":160, "mod":0}
let s:lib.kmap["?"] = {"map":"?", "code":47, "mod":s:lib.kmod.shift}
let s:lib.kmap["@"] = {"map":"@", "code":512, "mod":0}
let s:lib.kmap["A"] = {"map":"A", "code":65, "mod":s:lib.kmod.shift}
let s:lib.kmap["B"] = {"map":"B", "code":66, "mod":s:lib.kmod.shift}
let s:lib.kmap["C"] = {"map":"C", "code":67, "mod":s:lib.kmod.shift}
let s:lib.kmap["D"] = {"map":"D", "code":68, "mod":s:lib.kmod.shift}
let s:lib.kmap["E"] = {"map":"E", "code":69, "mod":s:lib.kmod.shift}
let s:lib.kmap["F"] = {"map":"F", "code":70, "mod":s:lib.kmod.shift}
let s:lib.kmap["G"] = {"map":"G", "code":71, "mod":s:lib.kmod.shift}
let s:lib.kmap["H"] = {"map":"H", "code":72, "mod":s:lib.kmod.shift}
let s:lib.kmap["I"] = {"map":"I", "code":73, "mod":s:lib.kmod.shift}
let s:lib.kmap["J"] = {"map":"J", "code":74, "mod":s:lib.kmod.shift}
let s:lib.kmap["K"] = {"map":"K", "code":75, "mod":s:lib.kmod.shift}
let s:lib.kmap["L"] = {"map":"L", "code":76, "mod":s:lib.kmod.shift}
let s:lib.kmap["M"] = {"map":"M", "code":77, "mod":s:lib.kmod.shift}
let s:lib.kmap["N"] = {"map":"N", "code":78, "mod":s:lib.kmod.shift}
let s:lib.kmap["O"] = {"map":"O", "code":79, "mod":s:lib.kmod.shift}
let s:lib.kmap["P"] = {"map":"P", "code":80, "mod":s:lib.kmod.shift}
let s:lib.kmap["Q"] = {"map":"Q", "code":81, "mod":s:lib.kmod.shift}
let s:lib.kmap["R"] = {"map":"R", "code":82, "mod":s:lib.kmod.shift}
let s:lib.kmap["S"] = {"map":"S", "code":83, "mod":s:lib.kmod.shift}
let s:lib.kmap["T"] = {"map":"T", "code":84, "mod":s:lib.kmod.shift}
let s:lib.kmap["U"] = {"map":"U", "code":85, "mod":s:lib.kmod.shift}
let s:lib.kmap["V"] = {"map":"V", "code":86, "mod":s:lib.kmod.shift}
let s:lib.kmap["W"] = {"map":"W", "code":87, "mod":s:lib.kmod.shift}
let s:lib.kmap["X"] = {"map":"X", "code":88, "mod":s:lib.kmod.shift}
let s:lib.kmap["Y"] = {"map":"Y", "code":89, "mod":s:lib.kmod.shift}
let s:lib.kmap["Z"] = {"map":"Z", "code":90, "mod":s:lib.kmod.shift}
let s:lib.kmap["["] = {"map":"[", "code":91, "mod":0}
let s:lib.kmap['\'] = {"map":"<BSlash>", "code":92, "mod":0}
let s:lib.kmap["]"] = {"map":"]", "code":93, "mod":0}
let s:lib.kmap["^"] = {"map":"^", "code":514, "mod":0}
let s:lib.kmap["_"] = {"map":"_", "code":523, "mod":0}
let s:lib.kmap["`"] = {"map":"`", "code":192, "mod":0}
let s:lib.kmap["a"] = {"map":"a", "code":65, "mod":0}
let s:lib.kmap["b"] = {"map":"b", "code":66, "mod":0}
let s:lib.kmap["c"] = {"map":"c", "code":67, "mod":0}
let s:lib.kmap["d"] = {"map":"d", "code":68, "mod":0}
let s:lib.kmap["e"] = {"map":"e", "code":69, "mod":0}
let s:lib.kmap["f"] = {"map":"f", "code":70, "mod":0}
let s:lib.kmap["g"] = {"map":"g", "code":71, "mod":0}
let s:lib.kmap["h"] = {"map":"h", "code":72, "mod":0}
let s:lib.kmap["i"] = {"map":"i", "code":73, "mod":0}
let s:lib.kmap["j"] = {"map":"j", "code":74, "mod":0}
let s:lib.kmap["k"] = {"map":"k", "code":75, "mod":0}
let s:lib.kmap["l"] = {"map":"l", "code":76, "mod":0}
let s:lib.kmap["m"] = {"map":"m", "code":77, "mod":0}
let s:lib.kmap["n"] = {"map":"n", "code":78, "mod":0}
let s:lib.kmap["o"] = {"map":"o", "code":79, "mod":0}
let s:lib.kmap["p"] = {"map":"p", "code":80, "mod":0}
let s:lib.kmap["q"] = {"map":"q", "code":81, "mod":0}
let s:lib.kmap["r"] = {"map":"r", "code":82, "mod":0}
let s:lib.kmap["s"] = {"map":"s", "code":83, "mod":0}
let s:lib.kmap["t"] = {"map":"t", "code":84, "mod":0}
let s:lib.kmap["u"] = {"map":"u", "code":85, "mod":0}
let s:lib.kmap["v"] = {"map":"v", "code":86, "mod":0}
let s:lib.kmap["w"] = {"map":"w", "code":87, "mod":0}
let s:lib.kmap["x"] = {"map":"x", "code":88, "mod":0}
let s:lib.kmap["y"] = {"map":"y", "code":89, "mod":0}
let s:lib.kmap["z"] = {"map":"z", "code":90, "mod":0}
let s:lib.kmap["{"] = {"map":"{", "code":161, "mod":0}
let s:lib.kmap["|"] = {"map":"<Bar>", "code":108, "mod":0}
let s:lib.kmap["}"] = {"map":"}", "code":162, "mod":0}
let s:lib.kmap["~"] = {"map":"~", "code":131, "mod":0}

" Since <Tab> and <C-I> has same key code, use <S-Tab> for <Tab>.
let s:lib.kmap["\<S-Tab>"] = {"map":"<S-Tab>", "code":9, "mod":0}
let s:lib.kmap["\<BS>"] = {"map":"<BS>", "code":8, "mod":0}
let s:lib.kmap["\<Del>"] = {"map":"<Del>", "code":127, "mod":0}
let s:lib.kmap["\<CR>"] = {"map":"<CR>", "code":10, "mod":0}
let s:lib.kmap["\<Left>"] = {"map":"<Left>", "code":37, "mod":0}
let s:lib.kmap["\<Up>"] = {"map":"<Up>", "code":38, "mod":0}
let s:lib.kmap["\<Right>"] = {"map":"<Right>", "code":39, "mod":0}
let s:lib.kmap["\<Down>"] = {"map":"<Down>", "code":40, "mod":0}
let s:lib.kmap["\<PageUp>"] = {"map":"<PageUp>", "code":33, "mod":0}
let s:lib.kmap["\<PageDown>"] = {"map":"<PageDown>", "code":34, "mod":0}
let s:lib.kmap["\<Home>"] = {"map":"<Home>", "code":36, "mod":0}
let s:lib.kmap["\<End>"] = {"map":"<End>", "code":35, "mod":0}
let s:lib.kmap["\<F1>"] = {"map":"<F1>", "code":112, "mod":0}
let s:lib.kmap["\<F2>"] = {"map":"<F2>", "code":113, "mod":0}
let s:lib.kmap["\<F3>"] = {"map":"<F3>", "code":114, "mod":0}
let s:lib.kmap["\<F4>"] = {"map":"<F4>", "code":115, "mod":0}
let s:lib.kmap["\<F5>"] = {"map":"<F5>", "code":116, "mod":0}
let s:lib.kmap["\<F6>"] = {"map":"<F6>", "code":117, "mod":0}
let s:lib.kmap["\<F7>"] = {"map":"<F7>", "code":118, "mod":0}
let s:lib.kmap["\<F8>"] = {"map":"<F8>", "code":119, "mod":0}
let s:lib.kmap["\<F9>"] = {"map":"<F9>", "code":120, "mod":0}
let s:lib.kmap["\<F10>"] = {"map":"<F10>", "code":121, "mod":0}
let s:lib.kmap["\<F11>"] = {"map":"<F11>", "code":122, "mod":0}
let s:lib.kmap["\<F12>"] = {"map":"<F12>", "code":123, "mod":0}
let s:lib.kmap["\<F13>"] = {"map":"<F13>", "code":61440, "mod":0}
let s:lib.kmap["\<F14>"] = {"map":"<F14>", "code":61441, "mod":0}
let s:lib.kmap["\<F15>"] = {"map":"<F15>", "code":61442, "mod":0}
let s:lib.kmap["\<F16>"] = {"map":"<F16>", "code":61443, "mod":0}
let s:lib.kmap["\<F17>"] = {"map":"<F17>", "code":61444, "mod":0}
let s:lib.kmap["\<F18>"] = {"map":"<F18>", "code":61445, "mod":0}
let s:lib.kmap["\<F19>"] = {"map":"<F19>", "code":61446, "mod":0}
let s:lib.kmap["\<F20>"] = {"map":"<F20>", "code":61447, "mod":0}
let s:lib.kmap["\<F21>"] = {"map":"<F21>", "code":61448, "mod":0}
let s:lib.kmap["\<F22>"] = {"map":"<F22>", "code":61449, "mod":0}
let s:lib.kmap["\<F23>"] = {"map":"<F23>", "code":61450, "mod":0}
let s:lib.kmap["\<F24>"] = {"map":"<F24>", "code":61451, "mod":0}

let s:lib.kmap["\<S-BS>"] = {"map":"<S-BS>", "code":8, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-Del>"] = {"map":"<S-Del>", "code":127, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-CR>"] = {"map":"<S-CR>", "code":10, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-Left>"] = {"map":"<S-Left>", "code":37, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-Up>"] = {"map":"<S-Up>", "code":38, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-Right>"] = {"map":"<S-Right>", "code":39, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-Down>"] = {"map":"<S-Down>", "code":40, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-PageUp>"] = {"map":"<S-PageUp>", "code":33, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-PageDown>"] = {"map":"<S-PageDown>", "code":34, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-Home>"] = {"map":"<S-Home>", "code":36, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-End>"] = {"map":"<S-End>", "code":35, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F1>"] = {"map":"<S-F1>", "code":112, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F2>"] = {"map":"<S-F2>", "code":113, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F3>"] = {"map":"<S-F3>", "code":114, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F4>"] = {"map":"<S-F4>", "code":115, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F5>"] = {"map":"<S-F5>", "code":116, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F6>"] = {"map":"<S-F6>", "code":117, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F7>"] = {"map":"<S-F7>", "code":118, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F8>"] = {"map":"<S-F8>", "code":119, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F9>"] = {"map":"<S-F9>", "code":120, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F10>"] = {"map":"<S-F10>", "code":121, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F11>"] = {"map":"<S-F11>", "code":122, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F12>"] = {"map":"<S-F12>", "code":123, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F13>"] = {"map":"<S-F13>", "code":61440, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F14>"] = {"map":"<S-F14>", "code":61441, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F15>"] = {"map":"<S-F15>", "code":61442, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F16>"] = {"map":"<S-F16>", "code":61443, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F17>"] = {"map":"<S-F17>", "code":61444, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F18>"] = {"map":"<S-F18>", "code":61445, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F19>"] = {"map":"<S-F19>", "code":61446, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F20>"] = {"map":"<S-F20>", "code":61447, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F21>"] = {"map":"<S-F21>", "code":61448, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F22>"] = {"map":"<S-F22>", "code":61449, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F23>"] = {"map":"<S-F23>", "code":61450, "mod":s:lib.kmod.shift}
let s:lib.kmap["\<S-F24>"] = {"map":"<S-F24>", "code":61451, "mod":s:lib.kmod.shift}

let s:lib.kmap["\<C-BS>"] = {"map":"<C-BS>", "code":8, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Del>"] = {"map":"<C-Del>", "code":127, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-CR>"] = {"map":"<C-CR>", "code":10, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Left>"] = {"map":"<C-Left>", "code":37, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Up>"] = {"map":"<C-Up>", "code":38, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Right>"] = {"map":"<C-Right>", "code":39, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Down>"] = {"map":"<C-Down>", "code":40, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-PageUp>"] = {"map":"<C-PageUp>", "code":33, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-PageDown>"] = {"map":"<C-PageDown>", "code":34, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-Home>"] = {"map":"<C-Home>", "code":36, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-End>"] = {"map":"<C-End>", "code":35, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F1>"] = {"map":"<C-F1>", "code":112, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F2>"] = {"map":"<C-F2>", "code":113, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F3>"] = {"map":"<C-F3>", "code":114, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F4>"] = {"map":"<C-F4>", "code":115, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F5>"] = {"map":"<C-F5>", "code":116, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F6>"] = {"map":"<C-F6>", "code":117, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F7>"] = {"map":"<C-F7>", "code":118, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F8>"] = {"map":"<C-F8>", "code":119, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F9>"] = {"map":"<C-F9>", "code":120, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F10>"] = {"map":"<C-F10>", "code":121, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F11>"] = {"map":"<C-F11>", "code":122, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F12>"] = {"map":"<C-F12>", "code":123, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F13>"] = {"map":"<C-F13>", "code":61440, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F14>"] = {"map":"<C-F14>", "code":61441, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F15>"] = {"map":"<C-F15>", "code":61442, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F16>"] = {"map":"<C-F16>", "code":61443, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F17>"] = {"map":"<C-F17>", "code":61444, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F18>"] = {"map":"<C-F18>", "code":61445, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F19>"] = {"map":"<C-F19>", "code":61446, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F20>"] = {"map":"<C-F20>", "code":61447, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F21>"] = {"map":"<C-F21>", "code":61448, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F22>"] = {"map":"<C-F22>", "code":61449, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F23>"] = {"map":"<C-F23>", "code":61450, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["\<C-F24>"] = {"map":"<C-F24>", "code":61451, "mod":s:lib.kmod.ctrl}

let s:lib.kmap["\<S-C-BS>"] = {"map":"<S-C-BS>", "code":8, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-Del>"] = {"map":"<S-C-Del>", "code":127, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-CR>"] = {"map":"<S-C-CR>", "code":10, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-Left>"] = {"map":"<S-C-Left>", "code":37, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-Up>"] = {"map":"<S-C-Up>", "code":38, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-Right>"] = {"map":"<S-C-Right>", "code":39, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-Down>"] = {"map":"<S-C-Down>", "code":40, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-PageUp>"] = {"map":"<S-C-PageUp>", "code":33, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-PageDown>"] = {"map":"<S-C-PageDown>", "code":34, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-Home>"] = {"map":"<S-C-Home>", "code":36, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-End>"] = {"map":"<S-C-End>", "code":35, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F1>"] = {"map":"<S-C-F1>", "code":112, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F2>"] = {"map":"<S-C-F2>", "code":113, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F3>"] = {"map":"<S-C-F3>", "code":114, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F4>"] = {"map":"<S-C-F4>", "code":115, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F5>"] = {"map":"<S-C-F5>", "code":116, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F6>"] = {"map":"<S-C-F6>", "code":117, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F7>"] = {"map":"<S-C-F7>", "code":118, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F8>"] = {"map":"<S-C-F8>", "code":119, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F9>"] = {"map":"<S-C-F9>", "code":120, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F10>"] = {"map":"<S-C-F10>", "code":121, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F11>"] = {"map":"<S-C-F11>", "code":122, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F12>"] = {"map":"<S-C-F12>", "code":123, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F13>"] = {"map":"<S-C-F13>", "code":61440, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F14>"] = {"map":"<S-C-F14>", "code":61441, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F15>"] = {"map":"<S-C-F15>", "code":61442, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F16>"] = {"map":"<S-C-F16>", "code":61443, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F17>"] = {"map":"<S-C-F17>", "code":61444, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F18>"] = {"map":"<S-C-F18>", "code":61445, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F19>"] = {"map":"<S-C-F19>", "code":61446, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F20>"] = {"map":"<S-C-F20>", "code":61447, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F21>"] = {"map":"<S-C-F21>", "code":61448, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F22>"] = {"map":"<S-C-F22>", "code":61449, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F23>"] = {"map":"<S-C-F23>", "code":61450, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}
let s:lib.kmap["\<S-C-F24>"] = {"map":"<S-C-F24>", "code":61451, "mod":s:lib.kmod.shift + s:lib.kmod.ctrl}

" There are special keys can not be mapped to.
let s:lib.kmap["<Kanji>"] = {"map":"", "code":25, "mod":0}
let s:lib.kmap["<Hiragana_Katakana>"] = {"map":"", "code":275, "mod":0}
let s:lib.kmap["<S-Space>"] = {"map":"", "code":32, "mod":s:lib.kmod.shift}
let s:lib.kmap["<C-Space>"] = {"map":"", "code":32, "mod":s:lib.kmod.ctrl}
let s:lib.kmap["<A-Space>"] = {"map":"", "code":32, "mod":s:lib.kmod.alt}
let s:lib.kmap["<M-Space>"] = {"map":"", "code":32, "mod":s:lib.kmod.alt}
let s:lib.kmap["<C-,>"] = {"map":"", "code":44, "mod":s:lib.kmod.ctrl}

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

