" 2007-03-12

scriptencoding utf-8

let s:cpo_save = &cpo
set cpo&vim

function uim#import()
  return s:lib
endfunction

function uim#info()
  call s:lib.init()
  for [method, langs, desc, is_default] in s:lib.get_imlist()
    echo printf("%s (%s) %s", method, join(langs, ', '), is_default ? "*default*" : "")
  endfor
endfunction

function uim#select()
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
    let b:uim_method = imlist[n - 1][0]
    let b:uim_lang   = imlist[n - 1][1][0]
    setlocal keymap=uim
  endif
endfunction

augroup Uim
  autocmd VimLeave * call s:lib.uninit()
augroup END

let s:lib = deepcopy(imbase#import())

"-----------------------------------------------------------
" LOW LEVEL API
let s:lib.api.dll = expand("<sfile>:p:h") . "/uim-vim.so"

function s:lib.api.load_key_constant()
  return self.libcall("load_key_constant", [])
endfunction

function! s:lib.api.uninit()
  if has("gui_running") && $GTK_IM_MODULE == "uim"
    " Don't invoke uim_quit() yet because uim-vim and uim-gtk are
    " running in same process.
    return []
  endif
  return self.libcall("uninit", [])
endfunction

"-----------------------------------------------------------
" Input Method
function! s:lib.init()
  if !self.initialized
    call self.api.load()
    call self.api.init()
    call self.load_key_constant()
    let self.initialized = 1
  endif
endfunction

"-----------------------------------------------------------
" Input Method Context
let s:lib.context.api = s:lib.api
let s:lib.context.kmap = s:lib.kmap   " TODO: Don't copy for each instance
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

    elseif event == "preedit_clear"
      let self.preedit = []

    elseif event == "preedit_pushback"
      let [str, attr] = remove(lis, 0, 1)
      " Check if string is empty. It is passed from some IM.
      " Maybe it is aim of keeping preedit window?
      if str != ""
        call add(self.preedit, [str, self.make_attr(attr)])
      endif

    elseif event == "candidate_activate"
      let [varname, pagesize, len] = remove(lis, 0, 2)
      let candidate = []
      for i in range(len)
        let [label, str, annotation] = remove(lis, 0, 2)
        call add(candidate, [label, str, annotation])
      endfor
      let self.candidate = candidate
      let self.candidate_page_size = pagesize

    elseif event == "candidate_select"
      let [candidate_current] = remove(lis, 0, 0)
      let self.candidate_current = candidate_current
      let self.candidate_page_first = candidate_current - (candidate_current % self.candidate_page_size)
      let self.candidate_page_last = min([self.candidate_page_first + self.candidate_page_size, len(self.candidate)]) - 1

    elseif event == "candidate_deactivate"
      let self.candidate = []

    elseif event == "property_list_update"
      " TODO: make menu
      let [str, method] = remove(lis, 0, 1)
      let self.method = method
      let self.status_label = self.method . ":"
      let self.property = []
      for line in split(str, "\n")
        let [op; val] = split(line, "\t", 1)
        if op == "branch"
          let d = {}
          let d["indication_id"]  = val[0]
          let d["iconic_label"]   = val[1]
          let d["iconic_string"]  = val[2]
          let self.status_label .= '[' . d["iconic_label"] . ']'
          call add(self.property, [])
        elseif op == "leaf"
          let d = {}
          let d["indication_id"]  = val[0]
          let d["iconic_label"]   = val[1]
          let d["iconic_string"]  = val[2]
          let d["short_desc"]     = val[3]
          let d["action_id"]      = val[4]
          let d["activity"]       = val[5]
          call add(self.property[-1], d)
        endif
      endfor

    else
      echoerr "Assertion: Unknown event " event
    endif
  endwhile
  return res
endfunction

function s:lib.context.make_attr(attr)
  let attr = []
  if a:attr % 2 != 0   " Attr_Underline
    call add(attr, "underline")
  endif
  if (a:attr / 2) % 2 != 0   " Attr_Reverse
    call add(attr, "reverse")
  endif
  if (a:attr / 4) % 2 != 0   " Attr_Cursor
    " pass
  endif
  if (a:attr / 8) % 2 != 0   " Attr_Separator
    " pass
  endif
  return join(attr, ",")
endfunction

"-----------------------------------------------------------
" Key mapping.

function s:lib.load_key_constant()
  " Since uim key is defined with enum and its value is not stable, get key
  " code from C code.
  let n2v = {}
  let lst = self.api.load_key_constant()
  while !empty(lst)
    let [name, code] = remove(lst, 0, 1)
    let n2v[name] = code + 0
  endwhile
  let self.kmod.shift    = n2v["UMod_Shift"]
  let self.kmod.ctrl     = n2v["UMod_Control"]
  let self.kmod.alt      = n2v["UMod_Alt"]
  let self.kmod.meta     = n2v["UMod_Meta"]
  let self.kmod.pseudo0  = n2v["UMod_Pseudo0"]
  let self.kmod.pseudo1  = n2v["UMod_Pseudo1"]
  let self.kmod.super    = n2v["UMod_Super"]
  let self.kmod.hyper    = n2v["UMod_Hyper"]
  for v in values(self.kmap)
    if type(v.code) == type("")
      let v.code = n2v[v.code]
    endif
    if type(v.mod) == type("")
      let mod = 0
      for mod_str in split(v.mod, '\s*|\s*')
        let mod += n2v[mod_str]
      endfor
      let v.mod = mod
    endif
  endfor
endfunction

" "UMod_*" and "UKey_*" are replaced with its Key Code when library is loaded.

let s:lib.kmap["\<C-A>"] = {"map":"<C-A>", "code":97, "mod":"UMod_Control"}
let s:lib.kmap["\<C-B>"] = {"map":"<C-B>", "code":98, "mod":"UMod_Control"}
" It is not useful to override <C-C>
" let s:lib.kmap["\<C-C>"] = {"map":"<C-C>", "code":99, "mod":"UMod_Control"}
let s:lib.kmap["\<C-D>"] = {"map":"<C-D>", "code":100, "mod":"UMod_Control"}
let s:lib.kmap["\<C-E>"] = {"map":"<C-E>", "code":101, "mod":"UMod_Control"}
let s:lib.kmap["\<C-F>"] = {"map":"<C-F>", "code":102, "mod":"UMod_Control"}
let s:lib.kmap["\<C-G>"] = {"map":"<C-G>", "code":103, "mod":"UMod_Control"}
let s:lib.kmap["\<C-H>"] = {"map":"<C-H>", "code":104, "mod":"UMod_Control"}
let s:lib.kmap["\<C-I>"] = {"map":"<C-I>", "code":105, "mod":"UMod_Control"}
let s:lib.kmap["\<C-J>"] = {"map":"<C-J>", "code":106, "mod":"UMod_Control"}
let s:lib.kmap["\<C-K>"] = {"map":"<C-K>", "code":107, "mod":"UMod_Control"}
let s:lib.kmap["\<C-L>"] = {"map":"<C-L>", "code":108, "mod":"UMod_Control"}
let s:lib.kmap["\<C-M>"] = {"map":"<C-M>", "code":109, "mod":"UMod_Control"}
let s:lib.kmap["\<C-N>"] = {"map":"<C-N>", "code":110, "mod":"UMod_Control"}
let s:lib.kmap["\<C-O>"] = {"map":"<C-O>", "code":111, "mod":"UMod_Control"}
let s:lib.kmap["\<C-P>"] = {"map":"<C-P>", "code":112, "mod":"UMod_Control"}
let s:lib.kmap["\<C-Q>"] = {"map":"<C-Q>", "code":113, "mod":"UMod_Control"}
let s:lib.kmap["\<C-R>"] = {"map":"<C-R>", "code":114, "mod":"UMod_Control"}
let s:lib.kmap["\<C-S>"] = {"map":"<C-S>", "code":115, "mod":"UMod_Control"}
let s:lib.kmap["\<C-T>"] = {"map":"<C-T>", "code":116, "mod":"UMod_Control"}
let s:lib.kmap["\<C-U>"] = {"map":"<C-U>", "code":117, "mod":"UMod_Control"}
let s:lib.kmap["\<C-V>"] = {"map":"<C-V>", "code":118, "mod":"UMod_Control"}
let s:lib.kmap["\<C-W>"] = {"map":"<C-W>", "code":119, "mod":"UMod_Control"}
let s:lib.kmap["\<C-X>"] = {"map":"<C-X>", "code":120, "mod":"UMod_Control"}
let s:lib.kmap["\<C-Y>"] = {"map":"<C-Y>", "code":121, "mod":"UMod_Control"}
let s:lib.kmap["\<C-Z>"] = {"map":"<C-Z>", "code":122, "mod":"UMod_Control"}
" Vim cannot distinguish <C-[> and <Esc>.  Use <Esc>.
" let s:lib.kmap["\<C-[>"] = {"map":"<C-[>", "code":91, "mod":"UMod_Control"}
let s:lib.kmap["\<C-[>"] = {"map":"<C-[>", "code":"UKey_Escape", "mod":0}
let s:lib.kmap["\<C-\>"] = {"map":'<C-\>', "code":92, "mod":"UMod_Control"}
let s:lib.kmap["\<C-]>"] = {"map":"<C-]>", "code":93, "mod":"UMod_Control"}
" this causes redraw problem when turn off langmap on cmdline.
" let s:lib.kmap["\<C-^>"] = {"map":"<C-^>", "code":94, "mod":"UMod_Control"}
let s:lib.kmap["\<C-_>"] = {"map":"<C-_>", "code":95, "mod":"UMod_Control"}
let s:lib.kmap[" "] = {"map":"<Space>", "code":32, "mod":0}
let s:lib.kmap["!"] = {"map":"!", "code":33, "mod":0}
let s:lib.kmap['"'] = {"map":'"', "code":34, "mod":0}
let s:lib.kmap["#"] = {"map":"#", "code":35, "mod":0}
let s:lib.kmap["$"] = {"map":"$", "code":36, "mod":0}
let s:lib.kmap["%"] = {"map":"%", "code":37, "mod":0}
let s:lib.kmap["&"] = {"map":"&", "code":38, "mod":0}
let s:lib.kmap["'"] = {"map":"'", "code":39, "mod":0}
let s:lib.kmap["("] = {"map":"(", "code":40, "mod":0}
let s:lib.kmap[")"] = {"map":")", "code":41, "mod":0}
let s:lib.kmap["*"] = {"map":"*", "code":42, "mod":0}
let s:lib.kmap["+"] = {"map":"+", "code":43, "mod":0}
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
let s:lib.kmap[":"] = {"map":":", "code":58, "mod":0}
let s:lib.kmap[";"] = {"map":";", "code":59, "mod":0}
let s:lib.kmap["<"] = {"map":"<", "code":60, "mod":0}
let s:lib.kmap["="] = {"map":"=", "code":61, "mod":0}
let s:lib.kmap[">"] = {"map":">", "code":62, "mod":0}
let s:lib.kmap["?"] = {"map":"?", "code":63, "mod":0}
let s:lib.kmap["@"] = {"map":"@", "code":64, "mod":0}
let s:lib.kmap["A"] = {"map":"A", "code":65, "mod":"UMod_Shift"}
let s:lib.kmap["B"] = {"map":"B", "code":66, "mod":"UMod_Shift"}
let s:lib.kmap["C"] = {"map":"C", "code":67, "mod":"UMod_Shift"}
let s:lib.kmap["D"] = {"map":"D", "code":68, "mod":"UMod_Shift"}
let s:lib.kmap["E"] = {"map":"E", "code":69, "mod":"UMod_Shift"}
let s:lib.kmap["F"] = {"map":"F", "code":70, "mod":"UMod_Shift"}
let s:lib.kmap["G"] = {"map":"G", "code":71, "mod":"UMod_Shift"}
let s:lib.kmap["H"] = {"map":"H", "code":72, "mod":"UMod_Shift"}
let s:lib.kmap["I"] = {"map":"I", "code":73, "mod":"UMod_Shift"}
let s:lib.kmap["J"] = {"map":"J", "code":74, "mod":"UMod_Shift"}
let s:lib.kmap["K"] = {"map":"K", "code":75, "mod":"UMod_Shift"}
let s:lib.kmap["L"] = {"map":"L", "code":76, "mod":"UMod_Shift"}
let s:lib.kmap["M"] = {"map":"M", "code":77, "mod":"UMod_Shift"}
let s:lib.kmap["N"] = {"map":"N", "code":78, "mod":"UMod_Shift"}
let s:lib.kmap["O"] = {"map":"O", "code":79, "mod":"UMod_Shift"}
let s:lib.kmap["P"] = {"map":"P", "code":80, "mod":"UMod_Shift"}
let s:lib.kmap["Q"] = {"map":"Q", "code":81, "mod":"UMod_Shift"}
let s:lib.kmap["R"] = {"map":"R", "code":82, "mod":"UMod_Shift"}
let s:lib.kmap["S"] = {"map":"S", "code":83, "mod":"UMod_Shift"}
let s:lib.kmap["T"] = {"map":"T", "code":84, "mod":"UMod_Shift"}
let s:lib.kmap["U"] = {"map":"U", "code":85, "mod":"UMod_Shift"}
let s:lib.kmap["V"] = {"map":"V", "code":86, "mod":"UMod_Shift"}
let s:lib.kmap["W"] = {"map":"W", "code":87, "mod":"UMod_Shift"}
let s:lib.kmap["X"] = {"map":"X", "code":88, "mod":"UMod_Shift"}
let s:lib.kmap["Y"] = {"map":"Y", "code":89, "mod":"UMod_Shift"}
let s:lib.kmap["Z"] = {"map":"Z", "code":90, "mod":"UMod_Shift"}
let s:lib.kmap["["] = {"map":"[", "code":91, "mod":0}
let s:lib.kmap['\'] = {"map":"<BSlash>", "code":92, "mod":0}
let s:lib.kmap["]"] = {"map":"]", "code":93, "mod":0}
let s:lib.kmap["^"] = {"map":"^", "code":94, "mod":0}
let s:lib.kmap["_"] = {"map":"_", "code":95, "mod":0}
let s:lib.kmap["`"] = {"map":"`", "code":96, "mod":0}
let s:lib.kmap["a"] = {"map":"a", "code":97, "mod":0}
let s:lib.kmap["b"] = {"map":"b", "code":98, "mod":0}
let s:lib.kmap["c"] = {"map":"c", "code":99, "mod":0}
let s:lib.kmap["d"] = {"map":"d", "code":100, "mod":0}
let s:lib.kmap["e"] = {"map":"e", "code":101, "mod":0}
let s:lib.kmap["f"] = {"map":"f", "code":102, "mod":0}
let s:lib.kmap["g"] = {"map":"g", "code":103, "mod":0}
let s:lib.kmap["h"] = {"map":"h", "code":104, "mod":0}
let s:lib.kmap["i"] = {"map":"i", "code":105, "mod":0}
let s:lib.kmap["j"] = {"map":"j", "code":106, "mod":0}
let s:lib.kmap["k"] = {"map":"k", "code":107, "mod":0}
let s:lib.kmap["l"] = {"map":"l", "code":108, "mod":0}
let s:lib.kmap["m"] = {"map":"m", "code":109, "mod":0}
let s:lib.kmap["n"] = {"map":"n", "code":110, "mod":0}
let s:lib.kmap["o"] = {"map":"o", "code":111, "mod":0}
let s:lib.kmap["p"] = {"map":"p", "code":112, "mod":0}
let s:lib.kmap["q"] = {"map":"q", "code":113, "mod":0}
let s:lib.kmap["r"] = {"map":"r", "code":114, "mod":0}
let s:lib.kmap["s"] = {"map":"s", "code":115, "mod":0}
let s:lib.kmap["t"] = {"map":"t", "code":116, "mod":0}
let s:lib.kmap["u"] = {"map":"u", "code":117, "mod":0}
let s:lib.kmap["v"] = {"map":"v", "code":118, "mod":0}
let s:lib.kmap["w"] = {"map":"w", "code":119, "mod":0}
let s:lib.kmap["x"] = {"map":"x", "code":120, "mod":0}
let s:lib.kmap["y"] = {"map":"y", "code":121, "mod":0}
let s:lib.kmap["z"] = {"map":"z", "code":122, "mod":0}
let s:lib.kmap["{"] = {"map":"{", "code":123, "mod":0}
let s:lib.kmap["|"] = {"map":"<Bar>", "code":124, "mod":0}
let s:lib.kmap["}"] = {"map":"}", "code":125, "mod":0}
let s:lib.kmap["~"] = {"map":"~", "code":126, "mod":0}

" Since <Tab> and <C-I> has same key code, use <S-Tab> for <Tab>.
let s:lib.kmap["\<S-Tab>"] = {"map":"<S-Tab>", "code":"UKey_Tab", "mod":0}
let s:lib.kmap["\<BS>"] = {"map":"<BS>", "code":"UKey_Backspace", "mod":0}
let s:lib.kmap["\<Del>"] = {"map":"<Del>", "code":"UKey_Delete", "mod":0}
let s:lib.kmap["\<CR>"] = {"map":"<CR>", "code":"UKey_Return", "mod":0}
let s:lib.kmap["\<Left>"] = {"map":"<Left>", "code":"UKey_Left", "mod":0}
let s:lib.kmap["\<Up>"] = {"map":"<Up>", "code":"UKey_Up", "mod":0}
let s:lib.kmap["\<Right>"] = {"map":"<Right>", "code":"UKey_Right", "mod":0}
let s:lib.kmap["\<Down>"] = {"map":"<Down>", "code":"UKey_Down", "mod":0}
let s:lib.kmap["\<PageUp>"] = {"map":"<PageUp>", "code":"UKey_Prior", "mod":0}
let s:lib.kmap["\<PageDown>"] = {"map":"<PageDown>", "code":"UKey_Next", "mod":0}
let s:lib.kmap["\<Home>"] = {"map":"<Home>", "code":"UKey_Home", "mod":0}
let s:lib.kmap["\<End>"] = {"map":"<End>", "code":"UKey_End", "mod":0}
let s:lib.kmap["\<F1>"] = {"map":"<F1>", "code":"UKey_F1", "mod":0}
let s:lib.kmap["\<F2>"] = {"map":"<F2>", "code":"UKey_F2", "mod":0}
let s:lib.kmap["\<F3>"] = {"map":"<F3>", "code":"UKey_F3", "mod":0}
let s:lib.kmap["\<F4>"] = {"map":"<F4>", "code":"UKey_F4", "mod":0}
let s:lib.kmap["\<F5>"] = {"map":"<F5>", "code":"UKey_F5", "mod":0}
let s:lib.kmap["\<F6>"] = {"map":"<F6>", "code":"UKey_F6", "mod":0}
let s:lib.kmap["\<F7>"] = {"map":"<F7>", "code":"UKey_F7", "mod":0}
let s:lib.kmap["\<F8>"] = {"map":"<F8>", "code":"UKey_F8", "mod":0}
let s:lib.kmap["\<F9>"] = {"map":"<F9>", "code":"UKey_F9", "mod":0}
let s:lib.kmap["\<F10>"] = {"map":"<F10>", "code":"UKey_F10", "mod":0}
let s:lib.kmap["\<F11>"] = {"map":"<F11>", "code":"UKey_F11", "mod":0}
let s:lib.kmap["\<F12>"] = {"map":"<F12>", "code":"UKey_F12", "mod":0}
let s:lib.kmap["\<F13>"] = {"map":"<F13>", "code":"UKey_F13", "mod":0}
let s:lib.kmap["\<F14>"] = {"map":"<F14>", "code":"UKey_F14", "mod":0}
let s:lib.kmap["\<F15>"] = {"map":"<F15>", "code":"UKey_F15", "mod":0}
let s:lib.kmap["\<F16>"] = {"map":"<F16>", "code":"UKey_F16", "mod":0}
let s:lib.kmap["\<F17>"] = {"map":"<F17>", "code":"UKey_F17", "mod":0}
let s:lib.kmap["\<F18>"] = {"map":"<F18>", "code":"UKey_F18", "mod":0}
let s:lib.kmap["\<F19>"] = {"map":"<F19>", "code":"UKey_F19", "mod":0}
let s:lib.kmap["\<F20>"] = {"map":"<F20>", "code":"UKey_F20", "mod":0}
let s:lib.kmap["\<F21>"] = {"map":"<F21>", "code":"UKey_F21", "mod":0}
let s:lib.kmap["\<F22>"] = {"map":"<F22>", "code":"UKey_F22", "mod":0}
let s:lib.kmap["\<F23>"] = {"map":"<F23>", "code":"UKey_F23", "mod":0}
let s:lib.kmap["\<F24>"] = {"map":"<F24>", "code":"UKey_F24", "mod":0}
let s:lib.kmap["\<F25>"] = {"map":"<F25>", "code":"UKey_F25", "mod":0}
let s:lib.kmap["\<F26>"] = {"map":"<F26>", "code":"UKey_F26", "mod":0}
let s:lib.kmap["\<F27>"] = {"map":"<F27>", "code":"UKey_F27", "mod":0}
let s:lib.kmap["\<F28>"] = {"map":"<F28>", "code":"UKey_F28", "mod":0}
let s:lib.kmap["\<F29>"] = {"map":"<F29>", "code":"UKey_F29", "mod":0}
let s:lib.kmap["\<F30>"] = {"map":"<F30>", "code":"UKey_F30", "mod":0}
let s:lib.kmap["\<F31>"] = {"map":"<F31>", "code":"UKey_F31", "mod":0}
let s:lib.kmap["\<F32>"] = {"map":"<F32>", "code":"UKey_F32", "mod":0}
let s:lib.kmap["\<F33>"] = {"map":"<F33>", "code":"UKey_F33", "mod":0}
let s:lib.kmap["\<F34>"] = {"map":"<F34>", "code":"UKey_F34", "mod":0}
let s:lib.kmap["\<F35>"] = {"map":"<F35>", "code":"UKey_F35", "mod":0}

let s:lib.kmap["\<S-BS>"] = {"map":"<S-BS>", "code":"UKey_Backspace", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-Del>"] = {"map":"<S-Del>", "code":"UKey_Delete", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-CR>"] = {"map":"<S-CR>", "code":"UKey_Return", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-Left>"] = {"map":"<S-Left>", "code":"UKey_Left", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-Up>"] = {"map":"<S-Up>", "code":"UKey_Up", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-Right>"] = {"map":"<S-Right>", "code":"UKey_Right", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-Down>"] = {"map":"<S-Down>", "code":"UKey_Down", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-PageUp>"] = {"map":"<S-PageUp>", "code":"UKey_Prior", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-PageDown>"] = {"map":"<S-PageDown>", "code":"UKey_Next", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-Home>"] = {"map":"<S-Home>", "code":"UKey_Home", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-End>"] = {"map":"<S-End>", "code":"UKey_End", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F1>"] = {"map":"<S-F1>", "code":"UKey_F1", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F2>"] = {"map":"<S-F2>", "code":"UKey_F2", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F3>"] = {"map":"<S-F3>", "code":"UKey_F3", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F4>"] = {"map":"<S-F4>", "code":"UKey_F4", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F5>"] = {"map":"<S-F5>", "code":"UKey_F5", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F6>"] = {"map":"<S-F6>", "code":"UKey_F6", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F7>"] = {"map":"<S-F7>", "code":"UKey_F7", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F8>"] = {"map":"<S-F8>", "code":"UKey_F8", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F9>"] = {"map":"<S-F9>", "code":"UKey_F9", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F10>"] = {"map":"<S-F10>", "code":"UKey_F10", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F11>"] = {"map":"<S-F11>", "code":"UKey_F11", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F12>"] = {"map":"<S-F12>", "code":"UKey_F12", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F13>"] = {"map":"<S-F13>", "code":"UKey_F13", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F14>"] = {"map":"<S-F14>", "code":"UKey_F14", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F15>"] = {"map":"<S-F15>", "code":"UKey_F15", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F16>"] = {"map":"<S-F16>", "code":"UKey_F16", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F17>"] = {"map":"<S-F17>", "code":"UKey_F17", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F18>"] = {"map":"<S-F18>", "code":"UKey_F18", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F19>"] = {"map":"<S-F19>", "code":"UKey_F19", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F20>"] = {"map":"<S-F20>", "code":"UKey_F20", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F21>"] = {"map":"<S-F21>", "code":"UKey_F21", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F22>"] = {"map":"<S-F22>", "code":"UKey_F22", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F23>"] = {"map":"<S-F23>", "code":"UKey_F23", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F24>"] = {"map":"<S-F24>", "code":"UKey_F24", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F25>"] = {"map":"<S-F25>", "code":"UKey_F25", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F26>"] = {"map":"<S-F26>", "code":"UKey_F26", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F27>"] = {"map":"<S-F27>", "code":"UKey_F27", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F28>"] = {"map":"<S-F28>", "code":"UKey_F28", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F29>"] = {"map":"<S-F29>", "code":"UKey_F29", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F30>"] = {"map":"<S-F30>", "code":"UKey_F30", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F31>"] = {"map":"<S-F31>", "code":"UKey_F31", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F32>"] = {"map":"<S-F32>", "code":"UKey_F32", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F33>"] = {"map":"<S-F33>", "code":"UKey_F33", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F34>"] = {"map":"<S-F34>", "code":"UKey_F34", "mod":"UMod_Shift"}
let s:lib.kmap["\<S-F35>"] = {"map":"<S-F35>", "code":"UKey_F35", "mod":"UMod_Shift"}

let s:lib.kmap["\<C-BS>"] = {"map":"<C-BS>", "code":"UKey_Backspace", "mod":"UMod_Control"}
let s:lib.kmap["\<C-Del>"] = {"map":"<C-Del>", "code":"UKey_Delete", "mod":"UMod_Control"}
let s:lib.kmap["\<C-CR>"] = {"map":"<C-CR>", "code":"UKey_Return", "mod":"UMod_Control"}
let s:lib.kmap["\<C-Left>"] = {"map":"<C-Left>", "code":"UKey_Left", "mod":"UMod_Control"}
let s:lib.kmap["\<C-Up>"] = {"map":"<C-Up>", "code":"UKey_Up", "mod":"UMod_Control"}
let s:lib.kmap["\<C-Right>"] = {"map":"<C-Right>", "code":"UKey_Right", "mod":"UMod_Control"}
let s:lib.kmap["\<C-Down>"] = {"map":"<C-Down>", "code":"UKey_Down", "mod":"UMod_Control"}
let s:lib.kmap["\<C-PageUp>"] = {"map":"<C-PageUp>", "code":"UKey_Prior", "mod":"UMod_Control"}
let s:lib.kmap["\<C-PageDown>"] = {"map":"<C-PageDown>", "code":"UKey_Next", "mod":"UMod_Control"}
let s:lib.kmap["\<C-Home>"] = {"map":"<C-Home>", "code":"UKey_Home", "mod":"UMod_Control"}
let s:lib.kmap["\<C-End>"] = {"map":"<C-End>", "code":"UKey_End", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F1>"] = {"map":"<C-F1>", "code":"UKey_F1", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F2>"] = {"map":"<C-F2>", "code":"UKey_F2", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F3>"] = {"map":"<C-F3>", "code":"UKey_F3", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F4>"] = {"map":"<C-F4>", "code":"UKey_F4", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F5>"] = {"map":"<C-F5>", "code":"UKey_F5", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F6>"] = {"map":"<C-F6>", "code":"UKey_F6", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F7>"] = {"map":"<C-F7>", "code":"UKey_F7", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F8>"] = {"map":"<C-F8>", "code":"UKey_F8", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F9>"] = {"map":"<C-F9>", "code":"UKey_F9", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F10>"] = {"map":"<C-F10>", "code":"UKey_F10", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F11>"] = {"map":"<C-F11>", "code":"UKey_F11", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F12>"] = {"map":"<C-F12>", "code":"UKey_F12", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F13>"] = {"map":"<C-F13>", "code":"UKey_F13", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F14>"] = {"map":"<C-F14>", "code":"UKey_F14", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F15>"] = {"map":"<C-F15>", "code":"UKey_F15", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F16>"] = {"map":"<C-F16>", "code":"UKey_F16", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F17>"] = {"map":"<C-F17>", "code":"UKey_F17", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F18>"] = {"map":"<C-F18>", "code":"UKey_F18", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F19>"] = {"map":"<C-F19>", "code":"UKey_F19", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F20>"] = {"map":"<C-F20>", "code":"UKey_F20", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F21>"] = {"map":"<C-F21>", "code":"UKey_F21", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F22>"] = {"map":"<C-F22>", "code":"UKey_F22", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F23>"] = {"map":"<C-F23>", "code":"UKey_F23", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F24>"] = {"map":"<C-F24>", "code":"UKey_F24", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F25>"] = {"map":"<C-F25>", "code":"UKey_F25", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F26>"] = {"map":"<C-F26>", "code":"UKey_F26", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F27>"] = {"map":"<C-F27>", "code":"UKey_F27", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F28>"] = {"map":"<C-F28>", "code":"UKey_F28", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F29>"] = {"map":"<C-F29>", "code":"UKey_F29", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F30>"] = {"map":"<C-F30>", "code":"UKey_F30", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F31>"] = {"map":"<C-F31>", "code":"UKey_F31", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F32>"] = {"map":"<C-F32>", "code":"UKey_F32", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F33>"] = {"map":"<C-F33>", "code":"UKey_F33", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F34>"] = {"map":"<C-F34>", "code":"UKey_F34", "mod":"UMod_Control"}
let s:lib.kmap["\<C-F35>"] = {"map":"<C-F35>", "code":"UKey_F35", "mod":"UMod_Control"}

let s:lib.kmap["\<S-C-BS>"] = {"map":"<S-C-BS>", "code":"UKey_Backspace", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-Del>"] = {"map":"<S-C-Del>", "code":"UKey_Delete", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-CR>"] = {"map":"<S-C-CR>", "code":"UKey_Return", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-Left>"] = {"map":"<S-C-Left>", "code":"UKey_Left", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-Up>"] = {"map":"<S-C-Up>", "code":"UKey_Up", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-Right>"] = {"map":"<S-C-Right>", "code":"UKey_Right", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-Down>"] = {"map":"<S-C-Down>", "code":"UKey_Down", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-PageUp>"] = {"map":"<S-C-PageUp>", "code":"UKey_Prior", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-PageDown>"] = {"map":"<S-C-PageDown>", "code":"UKey_Next", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-Home>"] = {"map":"<S-C-Home>", "code":"UKey_Home", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-End>"] = {"map":"<S-C-End>", "code":"UKey_End", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F1>"] = {"map":"<S-C-F1>", "code":"UKey_F1", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F2>"] = {"map":"<S-C-F2>", "code":"UKey_F2", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F3>"] = {"map":"<S-C-F3>", "code":"UKey_F3", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F4>"] = {"map":"<S-C-F4>", "code":"UKey_F4", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F5>"] = {"map":"<S-C-F5>", "code":"UKey_F5", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F6>"] = {"map":"<S-C-F6>", "code":"UKey_F6", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F7>"] = {"map":"<S-C-F7>", "code":"UKey_F7", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F8>"] = {"map":"<S-C-F8>", "code":"UKey_F8", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F9>"] = {"map":"<S-C-F9>", "code":"UKey_F9", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F10>"] = {"map":"<S-C-F10>", "code":"UKey_F10", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F11>"] = {"map":"<S-C-F11>", "code":"UKey_F11", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F12>"] = {"map":"<S-C-F12>", "code":"UKey_F12", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F13>"] = {"map":"<S-C-F13>", "code":"UKey_F13", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F14>"] = {"map":"<S-C-F14>", "code":"UKey_F14", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F15>"] = {"map":"<S-C-F15>", "code":"UKey_F15", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F16>"] = {"map":"<S-C-F16>", "code":"UKey_F16", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F17>"] = {"map":"<S-C-F17>", "code":"UKey_F17", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F18>"] = {"map":"<S-C-F18>", "code":"UKey_F18", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F19>"] = {"map":"<S-C-F19>", "code":"UKey_F19", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F20>"] = {"map":"<S-C-F20>", "code":"UKey_F20", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F21>"] = {"map":"<S-C-F21>", "code":"UKey_F21", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F22>"] = {"map":"<S-C-F22>", "code":"UKey_F22", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F23>"] = {"map":"<S-C-F23>", "code":"UKey_F23", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F24>"] = {"map":"<S-C-F24>", "code":"UKey_F24", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F25>"] = {"map":"<S-C-F25>", "code":"UKey_F25", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F26>"] = {"map":"<S-C-F26>", "code":"UKey_F26", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F27>"] = {"map":"<S-C-F27>", "code":"UKey_F27", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F28>"] = {"map":"<S-C-F28>", "code":"UKey_F28", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F29>"] = {"map":"<S-C-F29>", "code":"UKey_F29", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F30>"] = {"map":"<S-C-F30>", "code":"UKey_F30", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F31>"] = {"map":"<S-C-F31>", "code":"UKey_F31", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F32>"] = {"map":"<S-C-F32>", "code":"UKey_F32", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F33>"] = {"map":"<S-C-F33>", "code":"UKey_F33", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F34>"] = {"map":"<S-C-F34>", "code":"UKey_F34", "mod":"UMod_Shift|UMod_Control"}
let s:lib.kmap["\<S-C-F35>"] = {"map":"<S-C-F35>", "code":"UKey_F35", "mod":"UMod_Shift|UMod_Control"}

" There are special keys that Vim can not handle and map to.
let s:lib.kmap["<Zenkaku_Hankaku>"] = {"map":"", "code":"UKey_Zenkaku_Hankaku", "mod":0}
let s:lib.kmap["<Multi_key>"] = {"map":"", "code":"UKey_Multi_key", "mod":0}
let s:lib.kmap["<Mode_switch>"] = {"map":"", "code":"UKey_Mode_switch", "mod":0}
let s:lib.kmap["<Henkan_Mode>"] = {"map":"", "code":"UKey_Henkan_Mode", "mod":0}
let s:lib.kmap["<Muhenkan>"] = {"map":"", "code":"UKey_Muhenkan", "mod":0}
let s:lib.kmap["<Kanji>"] = {"map":"", "code":"UKey_Kanji", "mod":0}
let s:lib.kmap["<Hiragana_Katakana>"] = {"map":"", "code":"UKey_Hiragana_Katakana", "mod":0}
let s:lib.kmap["<S-Space>"] = {"map":"", "code":32, "mod":"UMod_Shift"}
let s:lib.kmap["<C-Space>"] = {"map":"", "code":32, "mod":"UMod_Control"}
let s:lib.kmap["<A-Space>"] = {"map":"", "code":32, "mod":"UMod_Alt"}
let s:lib.kmap["<M-Space>"] = {"map":"", "code":32, "mod":"UMod_Meta"}
let s:lib.kmap["<C-,>"] = {"map":"", "code":44, "mod":"UMod_Control"}

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

