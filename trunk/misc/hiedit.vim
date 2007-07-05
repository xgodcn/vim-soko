" graphical colorscheme editor
" Last Change:  2007-03-13
" Maintainer:   Yukihiro Nakadaira <yukihiro.nakadaira@gmail.com>
" License:      This file is placed in the public domain.
"
" Usage:
"   Load base colorscheme and source hiedit.vim
"   :edit foo.c
"   :colorscheme default
"   :source hiedit.vim
"   Then, click somewhere in foo.c to select highlight group.
"
"   To select highlight group that can't be clicked, use "[name]" button
"   or "[sample]" button.
"
"   hiedit.vim well works in default settings
"   $ gvim -u NONE -N -c "syntax on" \
"          -c "colorscheme desert" -c "so hiedit.vim" foo.c
"
" Mapping:
"   hiedit.vim requires 3-button mouse.
"   <LeftMouse>     select highlight group
"   <MiddleMouse>   clone current selected highlight group
"   <RightMouse>    pick color
"
"   These alternative keys are mapped.
"   :map <space> <LeftMouse>
"   :map <Enter> <LeftMouse>
"   :map 1 <LeftMouse>
"   :map 2 <MiddleMouse>
"   :map 3 <RightMouse>
"
" BUG:
"   8 color terminal is not fully supported.
"

if !has('gui_running') && index(["8", "16", "88", "256"], &t_Co) == -1
  echoerr "hiedit.vim requires GUI or 8/16/88/256 color terminal"
  finish
elseif !exists("syntax_on")
  echoerr "hiedit.vim requires :syntax on"
  finish
endif

let s:save_cpo = &cpo
set cpo&vim

map <expr> <LeftMouse> <SID>Click('<LeftMouse>')
map <expr> <MiddleMouse> <SID>Click('<MiddleMouse>')
map <expr> <RightMouse> <SID>Click('<RightMouse>')
map <expr> <RightRelease> <SID>Click('<RightRelease>')
map <expr> <space> <SID>Click('<space>')
map <expr> <CR> <SID>Click('<CR>')
map <expr> 1 <SID>Click('1')
map <expr> 2 <SID>Click('2')
map <expr> 3 <SID>Click('3')

noremap <SID><LeftMouse> <C-\><C-N><LeftMouse><LeftRelease>:call hiedit.click("left")<CR><LeftMouse>
noremap <SID><RightMouse> <C-\><C-N><LeftMouse><LeftRelease>:call hiedit.click("right")<CR><LeftMouse>
noremap <SID><MiddleMouse> <C-\><C-N><LeftMouse><LeftRelease>:call hiedit.click("middle")<CR><LeftMouse>
" disable popup menu
noremap <SID><RightRelease> <Nop>
noremap <SID><space> <C-\><C-N>:call hiedit.click("left", 0)<CR>
noremap <SID><Enter> <C-\><C-N>:call hiedit.click("left", 0)<CR>
noremap <SID>1 <C-\><C-N>:call hiedit.click("left", 0)<CR>
noremap <SID>3 <C-\><C-N>:call hiedit.click("right", 0)<CR>
noremap <SID>2 <C-\><C-N>:call hiedit.click("middle", 0)<CR>

function! <SID>Click(key)
  if bufwinnr('--EDITOR--') == -1
    return a:key
  else
    return "\<SNR>" . s:SID() . "_" . a:key
  endif
endfunction

function! s:SID()
  return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfun

let hiedit = {}

" these colors are recognized.
let hiedit.advance = 0
let hiedit.hlname_list = []

let hiedit.hlname_basic = [
      \ "Cursor",
      \ "lCursor",
      \ "CursorIM",
      \ "CursorColumn",
      \ "CursorLine",
      \ "Directory",
      \ "DiffAdd",
      \ "DiffChange",
      \ "DiffDelete",
      \ "DiffText",
      \ "ErrorMsg",
      \ "VertSplit",
      \ "Folded",
      \ "FoldColumn",
      \ "SignColumn",
      \ "IncSearch",
      \ "LineNr",
      \ "MatchParen",
      \ "ModeMsg",
      \ "MoreMsg",
      \ "Normal",
      \ "NonText",
      \ "Pmenu",
      \ "PmenuSel",
      \ "PmenuSbar",
      \ "PmenuThumb",
      \ "Question",
      \ "Search",
      \ "SpecialKey",
      \ "SpellBad",
      \ "SpellCap",
      \ "SpellLocal",
      \ "SpellRare",
      \ "StatusLine",
      \ "StatusLineNC",
      \ "TabLine",
      \ "TabLineFill",
      \ "TabLineSel",
      \ "Title",
      \ "Visual",
      \ "VisualNOS",
      \ "WarningMsg",
      \ "WildMenu",
      \ "Comment",
      \ "Constant",
      \ "Special",
      \ "Identifier",
      \ "Statement",
      \ "PreProc",
      \ "Type",
      \ "Underlined",
      \ "Ignore",
      \ "Error",
      \ "Todo"]

let hiedit.hlname_advance = [
      \ "String",
      \ "Character",
      \ "Number",
      \ "Boolean",
      \ "Float",
      \ "Function",
      \ "Conditional",
      \ "Repeat",
      \ "Label",
      \ "Operator",
      \ "Keyword",
      \ "Exception",
      \ "Include",
      \ "Define",
      \ "Macro",
      \ "PreCondit",
      \ "StorageClass",
      \ "Structure",
      \ "Typedef",
      \ "Tag",
      \ "SpecialChar",
      \ "Delimiter",
      \ "SpecialComment",
      \ "Debug",
      \ ]

let hiedit.hlname_list = sort(copy(hiedit.hlname_basic))

let hiedit.color_name2val = {
      \ "black": "#000000",
      \ "darkblue": "#00008b",
      \ "darkgreen": "#006400",
      \ "darkcyan": "#008b8b",
      \ "darkred": "#8b0000",
      \ "darkmagenta": "#8b008b",
      \ "brown": "#a52a2a", "darkyellow": "#bbbb00",
      \ "lightgray": "#d3d3d3", "lightgrey": "#d3d3d3", "gray": "#bebebe", "grey": "#bebebe",
      \ "darkgrey": "#a9a9a9", "darkgray": "#a9a9a9",
      \ "blue": "#0000ff", "lightblue": "#add8e6",
      \ "green": "#00ff00", "lightgreen": "#90ee90",
      \ "cyan": "#00ffff", "lightcyan": "#e0ffff",
      \ "red": "#ff0000", "lightred": "#ffa0a0",
      \ "magenta": "#ff00ff", "lightmagenta": "#ffa0ff",
      \ "yellow": "#ffff00", "lightyellow": "#ffffe0",
      \ "white": "#ffffff",
      \
      \ "snow": "#fffafa",
      \ "ghostwhite": "#f8f8ff",
      \ "whitesmoke": "#f5f5f5",
      \ "gainsboro": "#dcdcdc",
      \ "floralwhite": "#fffaf0",
      \ "oldlace": "#fdf5e6",
      \ "linen": "#faf0e6",
      \ "antiquewhite": "#faebd7",
      \ "papayawhip": "#ffefd5",
      \ "blanchedalmond": "#ffebcd",
      \ "bisque": "#ffe4c4",
      \ "peachpuff": "#ffdab9",
      \ "navajowhite": "#ffdead",
      \ "moccasin": "#ffe4b5",
      \ "cornsilk": "#fff8dc",
      \ "ivory": "#fffff0",
      \ "lemonchiffon": "#fffacd",
      \ "seashell": "#fff5ee",
      \ "honeydew": "#f0fff0",
      \ "mintcream": "#f5fffa",
      \ "azure": "#f0ffff",
      \ "aliceblue": "#f0f8ff",
      \ "lavender": "#e6e6fa",
      \ "lavenderblush": "#fff0f5",
      \ "mistyrose": "#ffe4e1",
      \ "darkslategray": "#2f4f4f",
      \ "darkslategrey": "#2f4f4f",
      \ "dimgray": "#696969",
      \ "dimgrey": "#696969",
      \ "slategray": "#708090",
      \ "slategrey": "#708090",
      \ "lightslategray": "#778899",
      \ "lightslategrey": "#778899",
      \ "midnightblue": "#191970",
      \ "navy": "#000080",
      \ "navyblue": "#000080",
      \ "cornflowerblue": "#6495ed",
      \ "darkslateblue": "#483d8b",
      \ "slateblue": "#6a5acd",
      \ "mediumslateblue": "#7b68ee",
      \ "lightslateblue": "#8470ff",
      \ "mediumblue": "#0000cd",
      \ "royalblue": "#4169e1",
      \ "dodgerblue": "#1e90ff",
      \ "deepskyblue": "#00bfff",
      \ "skyblue": "#87ceeb",
      \ "lightskyblue": "#87cefa",
      \ "steelblue": "#4682b4",
      \ "lightsteelblue": "#b0c4de",
      \ "powderblue": "#b0e0e6",
      \ "paleturquoise": "#afeeee",
      \ "darkturquoise": "#00ced1",
      \ "mediumturquoise": "#48d1cc",
      \ "turquoise": "#40e0d0",
      \ "cadetblue": "#5f9ea0",
      \ "mediumaquamarine": "#66cdaa",
      \ "aquamarine": "#7fffd4",
      \ "darkolivegreen": "#556b2f",
      \ "darkseagreen": "#8fbc8f",
      \ "seagreen": "#2e8b57",
      \ "mediumseagreen": "#3cb371",
      \ "lightseagreen": "#20b2aa",
      \ "palegreen": "#98fb98",
      \ "springgreen": "#00ff7f",
      \ "lawngreen": "#7cfc00",
      \ "chartreuse": "#7fff00",
      \ "mediumspringgreen": "#00fa9a",
      \ "greenyellow": "#adff2f",
      \ "limegreen": "#32cd32",
      \ "yellowgreen": "#9acd32",
      \ "forestgreen": "#228b22",
      \ "olivedrab": "#6b8e23",
      \ "darkkhaki": "#bdb76b",
      \ "khaki": "#f0e68c",
      \ "palegoldenrod": "#eee8aa",
      \ "lightgoldenrodyellow": "#fafad2",
      \ "gold": "#ffd700",
      \ "lightgoldenrod": "#eedd82",
      \ "goldenrod": "#daa520",
      \ "darkgoldenrod": "#b8860b",
      \ "rosybrown": "#bc8f8f",
      \ "indianred": "#cd5c5c",
      \ "saddlebrown": "#8b4513",
      \ "sienna": "#a0522d",
      \ "peru": "#cd853f",
      \ "burlywood": "#deb887",
      \ "beige": "#f5f5dc",
      \ "wheat": "#f5deb3",
      \ "sandybrown": "#f4a460",
      \ "tan": "#d2b48c",
      \ "chocolate": "#d2691e",
      \ "firebrick": "#b22222",
      \ "darksalmon": "#e9967a",
      \ "salmon": "#fa8072",
      \ "lightsalmon": "#ffa07a",
      \ "orange": "#ffa500",
      \ "darkorange": "#ff8c00",
      \ "coral": "#ff7f50",
      \ "lightcoral": "#f08080",
      \ "tomato": "#ff6347",
      \ "orangered": "#ff4500",
      \ "hotpink": "#ff69b4",
      \ "deeppink": "#ff1493",
      \ "pink": "#ffc0cb",
      \ "lightpink": "#ffb6c1",
      \ "palevioletred": "#db7093",
      \ "maroon": "#b03060",
      \ "mediumvioletred": "#c71585",
      \ "violetred": "#d02090",
      \ "violet": "#ee82ee",
      \ "plum": "#dda0dd",
      \ "orchid": "#da70d6",
      \ "mediumorchid": "#ba55d3",
      \ "darkorchid": "#9932cc",
      \ "darkviolet": "#9400d3",
      \ "blueviolet": "#8a2be2",
      \ "purple": "#a020f0",
      \ "mediumpurple": "#9370db",
      \ "thistle": "#d8bfd8",
      \ "snow1": "#fffafa",
      \ "snow2": "#eee9e9",
      \ "snow3": "#cdc9c9",
      \ "snow4": "#8b8989",
      \ "seashell1": "#fff5ee",
      \ "seashell2": "#eee5de",
      \ "seashell3": "#cdc5bf",
      \ "seashell4": "#8b8682",
      \ "antiquewhite1": "#ffefdb",
      \ "antiquewhite2": "#eedfcc",
      \ "antiquewhite3": "#cdc0b0",
      \ "antiquewhite4": "#8b8378",
      \ "bisque1": "#ffe4c4",
      \ "bisque2": "#eed5b7",
      \ "bisque3": "#cdb79e",
      \ "bisque4": "#8b7d6b",
      \ "peachpuff1": "#ffdab9",
      \ "peachpuff2": "#eecbad",
      \ "peachpuff3": "#cdaf95",
      \ "peachpuff4": "#8b7765",
      \ "navajowhite1": "#ffdead",
      \ "navajowhite2": "#eecfa1",
      \ "navajowhite3": "#cdb38b",
      \ "navajowhite4": "#8b795e",
      \ "lemonchiffon1": "#fffacd",
      \ "lemonchiffon2": "#eee9bf",
      \ "lemonchiffon3": "#cdc9a5",
      \ "lemonchiffon4": "#8b8970",
      \ "cornsilk1": "#fff8dc",
      \ "cornsilk2": "#eee8cd",
      \ "cornsilk3": "#cdc8b1",
      \ "cornsilk4": "#8b8878",
      \ "ivory1": "#fffff0",
      \ "ivory2": "#eeeee0",
      \ "ivory3": "#cdcdc1",
      \ "ivory4": "#8b8b83",
      \ "honeydew1": "#f0fff0",
      \ "honeydew2": "#e0eee0",
      \ "honeydew3": "#c1cdc1",
      \ "honeydew4": "#838b83",
      \ "lavenderblush1": "#fff0f5",
      \ "lavenderblush2": "#eee0e5",
      \ "lavenderblush3": "#cdc1c5",
      \ "lavenderblush4": "#8b8386",
      \ "mistyrose1": "#ffe4e1",
      \ "mistyrose2": "#eed5d2",
      \ "mistyrose3": "#cdb7b5",
      \ "mistyrose4": "#8b7d7b",
      \ "azure1": "#f0ffff",
      \ "azure2": "#e0eeee",
      \ "azure3": "#c1cdcd",
      \ "azure4": "#838b8b",
      \ "slateblue1": "#836fff",
      \ "slateblue2": "#7a67ee",
      \ "slateblue3": "#6959cd",
      \ "slateblue4": "#473c8b",
      \ "royalblue1": "#4876ff",
      \ "royalblue2": "#436eee",
      \ "royalblue3": "#3a5fcd",
      \ "royalblue4": "#27408b",
      \ "blue1": "#0000ff",
      \ "blue2": "#0000ee",
      \ "blue3": "#0000cd",
      \ "blue4": "#00008b",
      \ "dodgerblue1": "#1e90ff",
      \ "dodgerblue2": "#1c86ee",
      \ "dodgerblue3": "#1874cd",
      \ "dodgerblue4": "#104e8b",
      \ "steelblue1": "#63b8ff",
      \ "steelblue2": "#5cacee",
      \ "steelblue3": "#4f94cd",
      \ "steelblue4": "#36648b",
      \ "deepskyblue1": "#00bfff",
      \ "deepskyblue2": "#00b2ee",
      \ "deepskyblue3": "#009acd",
      \ "deepskyblue4": "#00688b",
      \ "skyblue1": "#87ceff",
      \ "skyblue2": "#7ec0ee",
      \ "skyblue3": "#6ca6cd",
      \ "skyblue4": "#4a708b",
      \ "lightskyblue1": "#b0e2ff",
      \ "lightskyblue2": "#a4d3ee",
      \ "lightskyblue3": "#8db6cd",
      \ "lightskyblue4": "#607b8b",
      \ "slategray1": "#c6e2ff",
      \ "slategray2": "#b9d3ee",
      \ "slategray3": "#9fb6cd",
      \ "slategray4": "#6c7b8b",
      \ "lightsteelblue1": "#cae1ff",
      \ "lightsteelblue2": "#bcd2ee",
      \ "lightsteelblue3": "#a2b5cd",
      \ "lightsteelblue4": "#6e7b8b",
      \ "lightblue1": "#bfefff",
      \ "lightblue2": "#b2dfee",
      \ "lightblue3": "#9ac0cd",
      \ "lightblue4": "#68838b",
      \ "lightcyan1": "#e0ffff",
      \ "lightcyan2": "#d1eeee",
      \ "lightcyan3": "#b4cdcd",
      \ "lightcyan4": "#7a8b8b",
      \ "paleturquoise1": "#bbffff",
      \ "paleturquoise2": "#aeeeee",
      \ "paleturquoise3": "#96cdcd",
      \ "paleturquoise4": "#668b8b",
      \ "cadetblue1": "#98f5ff",
      \ "cadetblue2": "#8ee5ee",
      \ "cadetblue3": "#7ac5cd",
      \ "cadetblue4": "#53868b",
      \ "turquoise1": "#00f5ff",
      \ "turquoise2": "#00e5ee",
      \ "turquoise3": "#00c5cd",
      \ "turquoise4": "#00868b",
      \ "cyan1": "#00ffff",
      \ "cyan2": "#00eeee",
      \ "cyan3": "#00cdcd",
      \ "cyan4": "#008b8b",
      \ "darkslategray1": "#97ffff",
      \ "darkslategray2": "#8deeee",
      \ "darkslategray3": "#79cdcd",
      \ "darkslategray4": "#528b8b",
      \ "aquamarine1": "#7fffd4",
      \ "aquamarine2": "#76eec6",
      \ "aquamarine3": "#66cdaa",
      \ "aquamarine4": "#458b74",
      \ "darkseagreen1": "#c1ffc1",
      \ "darkseagreen2": "#b4eeb4",
      \ "darkseagreen3": "#9bcd9b",
      \ "darkseagreen4": "#698b69",
      \ "seagreen1": "#54ff9f",
      \ "seagreen2": "#4eee94",
      \ "seagreen3": "#43cd80",
      \ "seagreen4": "#2e8b57",
      \ "palegreen1": "#9aff9a",
      \ "palegreen2": "#90ee90",
      \ "palegreen3": "#7ccd7c",
      \ "palegreen4": "#548b54",
      \ "springgreen1": "#00ff7f",
      \ "springgreen2": "#00ee76",
      \ "springgreen3": "#00cd66",
      \ "springgreen4": "#008b45",
      \ "green1": "#00ff00",
      \ "green2": "#00ee00",
      \ "green3": "#00cd00",
      \ "green4": "#008b00",
      \ "chartreuse1": "#7fff00",
      \ "chartreuse2": "#76ee00",
      \ "chartreuse3": "#66cd00",
      \ "chartreuse4": "#458b00",
      \ "olivedrab1": "#c0ff3e",
      \ "olivedrab2": "#b3ee3a",
      \ "olivedrab3": "#9acd32",
      \ "olivedrab4": "#698b22",
      \ "darkolivegreen1": "#caff70",
      \ "darkolivegreen2": "#bcee68",
      \ "darkolivegreen3": "#a2cd5a",
      \ "darkolivegreen4": "#6e8b3d",
      \ "khaki1": "#fff68f",
      \ "khaki2": "#eee685",
      \ "khaki3": "#cdc673",
      \ "khaki4": "#8b864e",
      \ "lightgoldenrod1": "#ffec8b",
      \ "lightgoldenrod2": "#eedc82",
      \ "lightgoldenrod3": "#cdbe70",
      \ "lightgoldenrod4": "#8b814c",
      \ "lightyellow1": "#ffffe0",
      \ "lightyellow2": "#eeeed1",
      \ "lightyellow3": "#cdcdb4",
      \ "lightyellow4": "#8b8b7a",
      \ "yellow1": "#ffff00",
      \ "yellow2": "#eeee00",
      \ "yellow3": "#cdcd00",
      \ "yellow4": "#8b8b00",
      \ "gold1": "#ffd700",
      \ "gold2": "#eec900",
      \ "gold3": "#cdad00",
      \ "gold4": "#8b7500",
      \ "goldenrod1": "#ffc125",
      \ "goldenrod2": "#eeb422",
      \ "goldenrod3": "#cd9b1d",
      \ "goldenrod4": "#8b6914",
      \ "darkgoldenrod1": "#ffb90f",
      \ "darkgoldenrod2": "#eead0e",
      \ "darkgoldenrod3": "#cd950c",
      \ "darkgoldenrod4": "#8b6508",
      \ "rosybrown1": "#ffc1c1",
      \ "rosybrown2": "#eeb4b4",
      \ "rosybrown3": "#cd9b9b",
      \ "rosybrown4": "#8b6969",
      \ "indianred1": "#ff6a6a",
      \ "indianred2": "#ee6363",
      \ "indianred3": "#cd5555",
      \ "indianred4": "#8b3a3a",
      \ "sienna1": "#ff8247",
      \ "sienna2": "#ee7942",
      \ "sienna3": "#cd6839",
      \ "sienna4": "#8b4726",
      \ "burlywood1": "#ffd39b",
      \ "burlywood2": "#eec591",
      \ "burlywood3": "#cdaa7d",
      \ "burlywood4": "#8b7355",
      \ "wheat1": "#ffe7ba",
      \ "wheat2": "#eed8ae",
      \ "wheat3": "#cdba96",
      \ "wheat4": "#8b7e66",
      \ "tan1": "#ffa54f",
      \ "tan2": "#ee9a49",
      \ "tan3": "#cd853f",
      \ "tan4": "#8b5a2b",
      \ "chocolate1": "#ff7f24",
      \ "chocolate2": "#ee7621",
      \ "chocolate3": "#cd661d",
      \ "chocolate4": "#8b4513",
      \ "firebrick1": "#ff3030",
      \ "firebrick2": "#ee2c2c",
      \ "firebrick3": "#cd2626",
      \ "firebrick4": "#8b1a1a",
      \ "brown1": "#ff4040",
      \ "brown2": "#ee3b3b",
      \ "brown3": "#cd3333",
      \ "brown4": "#8b2323",
      \ "salmon1": "#ff8c69",
      \ "salmon2": "#ee8262",
      \ "salmon3": "#cd7054",
      \ "salmon4": "#8b4c39",
      \ "lightsalmon1": "#ffa07a",
      \ "lightsalmon2": "#ee9572",
      \ "lightsalmon3": "#cd8162",
      \ "lightsalmon4": "#8b5742",
      \ "orange1": "#ffa500",
      \ "orange2": "#ee9a00",
      \ "orange3": "#cd8500",
      \ "orange4": "#8b5a00",
      \ "darkorange1": "#ff7f00",
      \ "darkorange2": "#ee7600",
      \ "darkorange3": "#cd6600",
      \ "darkorange4": "#8b4500",
      \ "coral1": "#ff7256",
      \ "coral2": "#ee6a50",
      \ "coral3": "#cd5b45",
      \ "coral4": "#8b3e2f",
      \ "tomato1": "#ff6347",
      \ "tomato2": "#ee5c42",
      \ "tomato3": "#cd4f39",
      \ "tomato4": "#8b3626",
      \ "orangered1": "#ff4500",
      \ "orangered2": "#ee4000",
      \ "orangered3": "#cd3700",
      \ "orangered4": "#8b2500",
      \ "red1": "#ff0000",
      \ "red2": "#ee0000",
      \ "red3": "#cd0000",
      \ "red4": "#8b0000",
      \ "deeppink1": "#ff1493",
      \ "deeppink2": "#ee1289",
      \ "deeppink3": "#cd1076",
      \ "deeppink4": "#8b0a50",
      \ "hotpink1": "#ff6eb4",
      \ "hotpink2": "#ee6aa7",
      \ "hotpink3": "#cd6090",
      \ "hotpink4": "#8b3a62",
      \ "pink1": "#ffb5c5",
      \ "pink2": "#eea9b8",
      \ "pink3": "#cd919e",
      \ "pink4": "#8b636c",
      \ "lightpink1": "#ffaeb9",
      \ "lightpink2": "#eea2ad",
      \ "lightpink3": "#cd8c95",
      \ "lightpink4": "#8b5f65",
      \ "palevioletred1": "#ff82ab",
      \ "palevioletred2": "#ee799f",
      \ "palevioletred3": "#cd6889",
      \ "palevioletred4": "#8b475d",
      \ "maroon1": "#ff34b3",
      \ "maroon2": "#ee30a7",
      \ "maroon3": "#cd2990",
      \ "maroon4": "#8b1c62",
      \ "violetred1": "#ff3e96",
      \ "violetred2": "#ee3a8c",
      \ "violetred3": "#cd3278",
      \ "violetred4": "#8b2252",
      \ "magenta1": "#ff00ff",
      \ "magenta2": "#ee00ee",
      \ "magenta3": "#cd00cd",
      \ "magenta4": "#8b008b",
      \ "orchid1": "#ff83fa",
      \ "orchid2": "#ee7ae9",
      \ "orchid3": "#cd69c9",
      \ "orchid4": "#8b4789",
      \ "plum1": "#ffbbff",
      \ "plum2": "#eeaeee",
      \ "plum3": "#cd96cd",
      \ "plum4": "#8b668b",
      \ "mediumorchid1": "#e066ff",
      \ "mediumorchid2": "#d15fee",
      \ "mediumorchid3": "#b452cd",
      \ "mediumorchid4": "#7a378b",
      \ "darkorchid1": "#bf3eff",
      \ "darkorchid2": "#b23aee",
      \ "darkorchid3": "#9a32cd",
      \ "darkorchid4": "#68228b",
      \ "purple1": "#9b30ff",
      \ "purple2": "#912cee",
      \ "purple3": "#7d26cd",
      \ "purple4": "#551a8b",
      \ "mediumpurple1": "#ab82ff",
      \ "mediumpurple2": "#9f79ee",
      \ "mediumpurple3": "#8968cd",
      \ "mediumpurple4": "#5d478b",
      \ "thistle1": "#ffe1ff",
      \ "thistle2": "#eed2ee",
      \ "thistle3": "#cdb5cd",
      \ "thistle4": "#8b7b8b",
      \ "gray0": "#000000",
      \ "grey0": "#000000",
      \ "gray1": "#030303",
      \ "grey1": "#030303",
      \ "gray2": "#050505",
      \ "grey2": "#050505",
      \ "gray3": "#080808",
      \ "grey3": "#080808",
      \ "gray4": "#0a0a0a",
      \ "grey4": "#0a0a0a",
      \ "gray5": "#0d0d0d",
      \ "grey5": "#0d0d0d",
      \ "gray6": "#0f0f0f",
      \ "grey6": "#0f0f0f",
      \ "gray7": "#121212",
      \ "grey7": "#121212",
      \ "gray8": "#141414",
      \ "grey8": "#141414",
      \ "gray9": "#171717",
      \ "grey9": "#171717",
      \ "gray10": "#1a1a1a",
      \ "grey10": "#1a1a1a",
      \ "gray11": "#1c1c1c",
      \ "grey11": "#1c1c1c",
      \ "gray12": "#1f1f1f",
      \ "grey12": "#1f1f1f",
      \ "gray13": "#212121",
      \ "grey13": "#212121",
      \ "gray14": "#242424",
      \ "grey14": "#242424",
      \ "gray15": "#262626",
      \ "grey15": "#262626",
      \ "gray16": "#292929",
      \ "grey16": "#292929",
      \ "gray17": "#2b2b2b",
      \ "grey17": "#2b2b2b",
      \ "gray18": "#2e2e2e",
      \ "grey18": "#2e2e2e",
      \ "gray19": "#303030",
      \ "grey19": "#303030",
      \ "gray20": "#333333",
      \ "grey20": "#333333",
      \ "gray21": "#363636",
      \ "grey21": "#363636",
      \ "gray22": "#383838",
      \ "grey22": "#383838",
      \ "gray23": "#3b3b3b",
      \ "grey23": "#3b3b3b",
      \ "gray24": "#3d3d3d",
      \ "grey24": "#3d3d3d",
      \ "gray25": "#404040",
      \ "grey25": "#404040",
      \ "gray26": "#424242",
      \ "grey26": "#424242",
      \ "gray27": "#454545",
      \ "grey27": "#454545",
      \ "gray28": "#474747",
      \ "grey28": "#474747",
      \ "gray29": "#4a4a4a",
      \ "grey29": "#4a4a4a",
      \ "gray30": "#4d4d4d",
      \ "grey30": "#4d4d4d",
      \ "gray31": "#4f4f4f",
      \ "grey31": "#4f4f4f",
      \ "gray32": "#525252",
      \ "grey32": "#525252",
      \ "gray33": "#545454",
      \ "grey33": "#545454",
      \ "gray34": "#575757",
      \ "grey34": "#575757",
      \ "gray35": "#595959",
      \ "grey35": "#595959",
      \ "gray36": "#5c5c5c",
      \ "grey36": "#5c5c5c",
      \ "gray37": "#5e5e5e",
      \ "grey37": "#5e5e5e",
      \ "gray38": "#616161",
      \ "grey38": "#616161",
      \ "gray39": "#636363",
      \ "grey39": "#636363",
      \ "gray40": "#666666",
      \ "grey40": "#666666",
      \ "gray41": "#696969",
      \ "grey41": "#696969",
      \ "gray42": "#6b6b6b",
      \ "grey42": "#6b6b6b",
      \ "gray43": "#6e6e6e",
      \ "grey43": "#6e6e6e",
      \ "gray44": "#707070",
      \ "grey44": "#707070",
      \ "gray45": "#737373",
      \ "grey45": "#737373",
      \ "gray46": "#757575",
      \ "grey46": "#757575",
      \ "gray47": "#787878",
      \ "grey47": "#787878",
      \ "gray48": "#7a7a7a",
      \ "grey48": "#7a7a7a",
      \ "gray49": "#7d7d7d",
      \ "grey49": "#7d7d7d",
      \ "gray50": "#7f7f7f",
      \ "grey50": "#7f7f7f",
      \ "gray51": "#828282",
      \ "grey51": "#828282",
      \ "gray52": "#858585",
      \ "grey52": "#858585",
      \ "gray53": "#878787",
      \ "grey53": "#878787",
      \ "gray54": "#8a8a8a",
      \ "grey54": "#8a8a8a",
      \ "gray55": "#8c8c8c",
      \ "grey55": "#8c8c8c",
      \ "gray56": "#8f8f8f",
      \ "grey56": "#8f8f8f",
      \ "gray57": "#919191",
      \ "grey57": "#919191",
      \ "gray58": "#949494",
      \ "grey58": "#949494",
      \ "gray59": "#969696",
      \ "grey59": "#969696",
      \ "gray60": "#999999",
      \ "grey60": "#999999",
      \ "gray61": "#9c9c9c",
      \ "grey61": "#9c9c9c",
      \ "gray62": "#9e9e9e",
      \ "grey62": "#9e9e9e",
      \ "gray63": "#a1a1a1",
      \ "grey63": "#a1a1a1",
      \ "gray64": "#a3a3a3",
      \ "grey64": "#a3a3a3",
      \ "gray65": "#a6a6a6",
      \ "grey65": "#a6a6a6",
      \ "gray66": "#a8a8a8",
      \ "grey66": "#a8a8a8",
      \ "gray67": "#ababab",
      \ "grey67": "#ababab",
      \ "gray68": "#adadad",
      \ "grey68": "#adadad",
      \ "gray69": "#b0b0b0",
      \ "grey69": "#b0b0b0",
      \ "gray70": "#b3b3b3",
      \ "grey70": "#b3b3b3",
      \ "gray71": "#b5b5b5",
      \ "grey71": "#b5b5b5",
      \ "gray72": "#b8b8b8",
      \ "grey72": "#b8b8b8",
      \ "gray73": "#bababa",
      \ "grey73": "#bababa",
      \ "gray74": "#bdbdbd",
      \ "grey74": "#bdbdbd",
      \ "gray75": "#bfbfbf",
      \ "grey75": "#bfbfbf",
      \ "gray76": "#c2c2c2",
      \ "grey76": "#c2c2c2",
      \ "gray77": "#c4c4c4",
      \ "grey77": "#c4c4c4",
      \ "gray78": "#c7c7c7",
      \ "grey78": "#c7c7c7",
      \ "gray79": "#c9c9c9",
      \ "grey79": "#c9c9c9",
      \ "gray80": "#cccccc",
      \ "grey80": "#cccccc",
      \ "gray81": "#cfcfcf",
      \ "grey81": "#cfcfcf",
      \ "gray82": "#d1d1d1",
      \ "grey82": "#d1d1d1",
      \ "gray83": "#d4d4d4",
      \ "grey83": "#d4d4d4",
      \ "gray84": "#d6d6d6",
      \ "grey84": "#d6d6d6",
      \ "gray85": "#d9d9d9",
      \ "grey85": "#d9d9d9",
      \ "gray86": "#dbdbdb",
      \ "grey86": "#dbdbdb",
      \ "gray87": "#dedede",
      \ "grey87": "#dedede",
      \ "gray88": "#e0e0e0",
      \ "grey88": "#e0e0e0",
      \ "gray89": "#e3e3e3",
      \ "grey89": "#e3e3e3",
      \ "gray90": "#e5e5e5",
      \ "grey90": "#e5e5e5",
      \ "gray91": "#e8e8e8",
      \ "grey91": "#e8e8e8",
      \ "gray92": "#ebebeb",
      \ "grey92": "#ebebeb",
      \ "gray93": "#ededed",
      \ "grey93": "#ededed",
      \ "gray94": "#f0f0f0",
      \ "grey94": "#f0f0f0",
      \ "gray95": "#f2f2f2",
      \ "grey95": "#f2f2f2",
      \ "gray96": "#f5f5f5",
      \ "grey96": "#f5f5f5",
      \ "gray97": "#f7f7f7",
      \ "grey97": "#f7f7f7",
      \ "gray98": "#fafafa",
      \ "grey98": "#fafafa",
      \ "gray99": "#fcfcfc",
      \ "grey99": "#fcfcfc",
      \ "gray100": "#ffffff",
      \ "grey100": "#ffffff"
      \ }

let hiedit.color_val2name = {}
for [s:name,s:color] in items(hiedit.color_name2val)
  if !has_key(hiedit.color_val2name, s:color) || s:name !~ '\d$\|grey'
    let hiedit.color_val2name[s:color] = s:name
  endif
endfor
unlet s:name s:color

function hiedit.getcolorvalue(color)
  let color = tolower(a:color)
  return get(self.color_name2val, color, color)
endfunction

function hiedit.getcolorname(color)
  let color = tolower(a:color)
  return get(self.color_val2name, color, color)
endfunction

let hiedit.attr = {
      \ "name": "",
      \ "cleared": 0,
      \ "link": "",
      \ "fg": "",
      \ "bg": "",
      \ "sp": "",
      \ "bold": 0,
      \ "italic": 0,
      \ "reverse": 0,
      \ "underline": 0,
      \ "undercurl": 0
      \ }

let hiedit.orig_attr = {}
let hiedit.use_gui = 0
let hiedit.colors_name = get(g:, "colors_name", "YOUR COLOR NAME")

let s:button_color = {"left":"fg", "right":"bg", "middle":"sp"}

function hiedit.click(button, ...)
  let self.use_gui = get(a:000, 0, has('gui_running'))
  if bufname("%") == "--EDITOR--"
    let name = synIDattr(synID(line('.'), col('.'), 1), "name")
    if name == "" || name[0] == "x"
      call self.form_click(a:button)
      return
    endif
    if self.attr["link"] != ""
      call self.copy_link()
    endif
    let type = s:button_color[a:button]
    let attr = self.getattr(name)
    if &t_Co == 8
      if type != "fg" && attr["bold"]
        echoerr "In 8 color term, this color can only be used for foreground (try reverse)"
        return
      endif
      if type == "fg"
        let self.attr["bold"] = attr["bold"]
      endif
    endif
    let self.attr[type] = attr["bg"]
    if name[0] == "p"
      call self.update_cache(self.attr[type])
      call self.update_luminance(self.attr[type])
    elseif name[0] == "c"
      call self.update_luminance(self.attr[type])
    elseif name[0] =~ '[wkrgb]'
      call self.update_cache(self.attr[type])
      call self.update_luminance(self.attr[type], name[0])
    endif
    call self.update_form()
  else
    let id = synID(line('.'), col('.'), 1)
    let name = synIDattr(id, 'name')
    let attr = self.getattr((name == "") ? "Normal" : name)
    let lst = []
    while index(self.hlname_list, attr["name"]) == -1
      if attr["link"] == ""
        if index(self.hlname_advance, attr["name"]) != -1
          unlet self.hlname_advance[index(self.hlname_advance, attr["name"]]
          call add(self.hlname_basic, attr["name"])
          let self.hlname_list = sort(copy(self.hlname_basic))
          break
        elseif attr["cleared"] || index(lst, attr["name"]) != -1
          let attr = self.getattr("Normal")
          break
        else
          echo "Unknown Highlight Group: " . attr["name"]
          return
        endif
        call add(lst, attr["name"])
      endif
      let attr = self.getattr(attr["link"])
    endwhile
    if a:button == "left"
      call self.select_name(attr["name"])
      wincmd p
    elseif a:button == "right"
      let name = synIDattr(synIDtrans(id), 'name')
      let attr = self.getattr((name == "") ? "Normal" : name)
      let nattr = self.getattr("Normal")
      if attr["fg"] == ""
        let attr["fg"] = (nattr["fg"] == "") ? "#FFFFFF" : nattr["fg"]
      endif
      if attr["bg"] == ""
        let attr["bg"] = (nattr["bg"] == "") ? "#000000" : nattr["bg"]
      endif
      if attr["reverse"]
        let tmp = attr["fg"]
        let attr["fg"] = attr["bg"]
        let attr["bg"] = tmp
      endif
      call self.set_special_palette("pick", attr)
    elseif a:button == "middle"
      let name = attr["name"]
      let attr = copy(self.attr)
      let attr["name"] = name
      call self.setattr(attr)
    endif
  endif
endfunction

function hiedit.form_click(button)
  let line = getline('.')
  if line[col('.')-1] == ']'
    let a = matchstr(line[:col('.')-2], '\[\zs[^\[\]]*$')
    let b = matchstr(line[col('.')-1:], '^[^\[\]]*\ze\]')
  else
    let a = matchstr(line[:col('.')-1], '\[\zs[^\[\]]*$')
    let b = matchstr(line[col('.'):], '^[^\[\]]*\ze\]')
  endif
  let [id, value; _] = split(a . b, ':', 1) + ["", ""]
  if id == "save"
    call self.save_script()
  elseif id == "sample"
    if bufexists("--SAMPLE--")
      bwipeout --SAMPLE--
    else
      call self.create_sample_window()
    endif
  elseif id == "reset"
    if has_key(self.orig_attr, self.attr["name"])
      let self.attr = copy(self.orig_attr[self.attr["name"]])
      call self.update_form()
    endif
  elseif id == "cls"
    if self.attr[s:button_color[a:button]] != ""
      if self.attr["link"] != ""
        call self.copy_link()
      endif
      let self.attr[s:button_color[a:button]] = ""
      call self.update_form()
    endif
  elseif id == "colors_name"
    try
      let name = inputdialog("type your colorscheme name: ", self.colors_name, "__cancel")
    catch /Vim:Interrupt/
      let name = "__cancel"
    endtry
    if name != "" && name != "__cancel"
      let self.colors_name = name
      call self.update_form(0)
    endif
  elseif id == "name"
    call self.popup(filter(copy(self.hlname_list), 'v:val != self.attr["name"]'), "select_name")
  elseif id == "link"
    let none = (self.attr["link"] == "") ? [] : ["[None]"]
    call self.popup(none + filter(copy(self.hlname_list), 'v:val != self.attr["name"]'), "select_link")
  elseif id == "fg" || id == "bg" || id == "sp"
    let color = inputdialog(id . " #RRGGBB or color name/number: ", (has('gui_running') && &guioptions =~ 'c') ? self.attr[id] : "", 'cancel')
    if color != 'cancel'
      if color =~ '^[0-9A-Fa-f]$'
        let color = self.palette[str2nr(color, 16)]
      elseif color =~ '^\d\+$' && 0 <= color && color < len(self.palette)
        let color = self.palette[color]
      endif
      if &t_Co == 8
        let n = index(self.palette, color)
        if n != -1 && n < 16
          if n > 7 && id != "fg"
            echoerr "In 8 color term, this color can only be used for foreground (try reverse)"
            return
          endif
          if self.attr["link"] != ""
            call self.copy_link()
          endif
          if id == "fg"
            let self.attr["bold"] = (n > 7)
          endif
          let color = self.palette[(n > 7) ? (n - 8) : n]
          let self.attr[id] = self.palette[(n > 7) ? (n - 8) : n]
          call self.update_form()
          return
        endif
      endif
      let color = self.getcolorvalue(color)
      if (color == "" || color =~ '^#[0-9A-Fa-f]\{6}$') && self.attr[id] !=? color
        if self.attr["link"] != ""
          call self.copy_link()
        endif
        let self.attr[id] = color
        call self.update_form()
        if color != ""
          call self.update_cache(color)
          call self.update_luminance(color)
        endif
      endif
    endif
  elseif id =~ 'bold\|italic\|reverse\|underline\|undercurl'
    if self.attr["link"] != ""
      call self.copy_link()
    endif
    let self.attr[id] = !self.attr[id]
    call self.update_form()
  elseif id == "background"
    let &background = (&background == "light") ? "dark" : "light"
    call self.reset_screen()
  elseif id == "advance"
    let self.advance = !self.advance
    if self.advance
      let self.hlname_list = sort(self.hlname_basic + self.hlname_advance)
    else
      let self.hlname_list = sort(copy(self.hlname_basic))
    endif
    call self.update_form(0)
  elseif id == "use_colorname"
    let self.use_colorname = !self.use_colorname
    call self.update_form()
  endif
endfunction

function hiedit.copy_link()
  let name = self.attr["name"]
  let self.attr = self.getattr(synIDattr(synIDtrans(hlID(self.attr["link"])), "name"))
  let self.attr["name"] = name
  call self.update_form()
endfunction

let hiedit.lu_num = 32

function hiedit.update_cache(color)
  if !has('gui_running')
    return
  endif
  for i in range(self.lu_num - 1, 1, -1)
    let color = synIDattr(hlID("c_" . (i - 1)), "bg#", "gui")
    execute printf("hi c_%d guifg=%s guibg=%s", i, color, color)
  endfor
  execute printf("hi c_0 guifg=%s guibg=%s", a:color, a:color)
endfunction

function hiedit.update_luminance(color, ...)
  if !has('gui_running')
    return
  endif
  let selected = get(a:000, 0, "xxx")
  let num = self.lu_num
  let color = a:color
  let red = str2nr(color[1:2], 16)
  let green = str2nr(color[3:4], 16)
  let blue = str2nr(color[5:6], 16)
  if selected != "w"
    let rd = 255 - red
    let gd = 255 - green
    let bd = 255 - blue
    for i in range(num)
      let r = red + (0x100 * rd / num * i / 0x100)
      let r = (r > 255 || i == (num - 1)) ? 255 : r
      let g = green + (0x100 * gd / num * i / 0x100)
      let g = (g > 255 || i == (num - 1)) ? 255 : g
      let b = blue + (0x100 * bd / num * i / 0x100)
      let b = (b > 255 || i == (num - 1)) ? 255 : b
      let color = printf("#%02X%02X%02X", r, g, b)
      execute printf("hi w_%d guifg=%s guibg=%s", num - i - 1, color, color)
    endfor
  endif
  if selected != "k"
    for i in range(num)
      let r = 0x100 * red / num * i / 0x100
      let r = (r < 0 || i == 0) ? 0 : r
      let g = 0x100 * green / num * i / 0x100
      let g = (g < 0 || i == 0) ? 0 : g
      let b = 0x100 * blue / num * i / 0x100
      let b = (b < 0 || i == 0) ? 0 : b
      let color = printf("#%02X%02X%02X", r, g, b)
      execute printf("hi k_%d guifg=%s guibg=%s", i, color, color)
    endfor
  endif
  if selected != "r"
    for i in range(num)
      let r = (i == num) ? 255 : (i * 256 / num)
      let g = green
      let b = blue
      let color = printf("#%02X%02X%02X", r, g, b)
      execute printf("hi r_%d guifg=%s guibg=%s", i, color, color)
    endfor
  endif
  if selected != "g"
    for i in range(num)
      let r = red
      let g = (i == num) ? 255 : (i * 256 / num)
      let b = blue
      let color = printf("#%02X%02X%02X", r, g, b)
      execute printf("hi g_%d guifg=%s guibg=%s", i, color, color)
    endfor
  endif
  if selected != "b"
    for i in range(num)
      let r = red
      let g = green
      let b = (i == num) ? 255 : (i * 256 / num)
      let color = printf("#%02X%02X%02X", r, g, b)
      execute printf("hi b_%d guifg=%s guibg=%s", i, color, color)
    endfor
  endif
endfunction

function hiedit.set_special_palette(type, attr)
  let attr = {}
  let attr["bold"] = a:attr["bold"]
  let attr["bg"] = a:attr["fg"]
  call self.pal_setattr(printf("p_%s_fg", a:type), attr)
  let attr["bold"] = 0
  let attr["bg"] = a:attr["bg"]
  call self.pal_setattr(printf("p_%s_bg", a:type), attr)
  let attr["bg"] = a:attr["sp"]
  call self.pal_setattr(printf("p_%s_sp", a:type), attr)
endfunction

function hiedit.pal_setattr(name, attr)
  let color = a:attr["bg"]
  let color = (color == "") ? "#000000" : color
  let n = index(self.palette, color)
  let n = (n == -1) ? 0 : n
  if &t_Co == 8 && a:attr["bold"]
    execute printf("hi %s guifg=%s guibg=%s cterm=bold ctermfg=%d ctermbg=%d", a:name, color, color, n, n)
  else
    execute printf("hi %s guifg=%s guibg=%s cterm=NONE ctermfg=%d ctermbg=%d", a:name, color, color, (n == 7) ? 0 : n, n)
  endif
endfunction

function hiedit.update_form(...)
  let update_hi = get(a:000, 0, 1)
  execute printf("%dwincmd w", bufwinnr("--EDITOR--"))
  call setline(1, printf("[save] [sample] [reset] [cls]    [colors_name:%s]", self.colors_name))
  call setline(line('$') - 3, printf("[name:%s] [fg:%s] [bg:%s] [sp:%s] [link:%s]",
        \ self.attr["name"], self.getfg(self.attr), self.attr["bg"], self.attr["sp"],
        \ self.attr["link"]))
  call setline(line('$') - 2, printf("[bold:%d] [italic:%d] [reverse:%d] [underline:%d] [undercurl:%d]",
        \ self.attr["bold"], self.attr["italic"], self.attr["reverse"],
        \ self.attr["underline"], self.attr["undercurl"]))
  call setline(line('$') - 1, printf("[background:%s] [advance:%d] [use_colorname:%d]", &background, self.advance, self.use_colorname))
  call setline(line('$'), ":" . self.make_hi_cmd(self.attr))
  for lnum in [1] + range(line('$') - 3, line('$'))
    call setline(lnum, printf("% -68s", getline(lnum)))
  endfor
  if update_hi
    call self.setattr(self.attr)
  endif
endfunction

function hiedit.save_script()
  new
  let attr = self.getattr("Normal")
  let n = index(self.palette, attr["bg"])
  if n == -1
    call setline(1, 'set background&')
  elseif n < 8
    "                  0123456789ABCDEF
    "         8 color: dllldlll
    " 16/88/256 color: dddddddldlllllll
    if n == 0 || n == 4 || n == 7
      call setline(1, 'set background=' . &background)
    else
      call setline(1, 'let &background = (&t_Co == 8) ? "light" : "dark"')
    endif
  else
    call setline(1, 'set background=' . &background)
  endif
  call append('$', 'hi clear')
  call append('$', 'if exists("syntax_on")')
  call append('$', '  syntax reset')
  call append('$', 'endif')
  call append('$', 'let g:colors_name = "' . self.colors_name . '"')
  call append('$', '')
  for name in self.hlname_list
    let attr = self.getattr(name)
    if attr["link"] == ""
      call append('$', self.make_hi_cmd(attr))
    endif
  endfor
  for name in self.hlname_list
    let attr = self.getattr(name)
    if attr["link"] != ""
      call append('$', self.make_hi_cmd(attr))
    endif
  endfor
  try
    if self.use_gui
      browse confirm write
    else
      let fname = input("save file: ", "", "file")
      if fname != ""
        confirm write `=fname`
      endif
    endif
  catch
    " void
  finally
    bwipeout!
  endtry
  execute printf("%dwincmd w", bufwinnr("--EDITOR--"))
endfunction

function hiedit.popup(lst, callback)
  silent! nunmenu ]HiMenu
  for i in range(len(a:lst))
    execute printf("nnoremenu 1.%d ]HiMenu.%s :call hiedit.%s('%s')<CR>", i, escape(a:lst[i], " "), a:callback, a:lst[i])
  endfor
  if self.use_gui
    popup ]HiMenu
  else
    call feedkeys("\<C-\>\<C-N>:emenu ]HiMenu.\<C-D>", "t")
  endif
endfunction

function hiedit.select_name(name)
  let self.attr = self.getattr(a:name)
  call self.set_special_palette("cur", self.attr)
  call self.update_form(0)
endfunction

function hiedit.select_link(name)
  let name = (a:name == "[None]") ? "" : a:name
  let self.attr["cleared"] = 0
  let self.attr["link"] = name
  let self.attr["fg"] = ""
  let self.attr["bg"] = ""
  let self.attr["bold"] = 0
  let self.attr["italic"] = 0
  let self.attr["reverse"] = 0
  let self.attr["underline"] = 0
  let self.attr["undercurl"] = 0
  call self.update_form()
endfunction

let hiedit.use_colorname = 0

function hiedit.make_hi_cmd(attr)
  if a:attr["link"] != ""
    return printf("hi link %s %s", a:attr["name"], a:attr["link"])
  endif
  let attrs = []
  if a:attr["bold"]
    call add(attrs, "bold")
  endif
  if a:attr["italic"]
    call add(attrs, "italic")
  endif
  if a:attr["reverse"]
    call add(attrs, "reverse")
  endif
  if a:attr["underline"]
    call add(attrs, "underline")
  endif
  if a:attr["undercurl"]
    call add(attrs, "undercurl")
  endif
  let gui = printf(" gui=%s", (attrs == []) ? "NONE" : join(attrs, ','))
  if a:attr["fg"] != ""
    let fg = self.getfg(a:attr)
    let gui .= " guifg=" . self.getguicolor(fg)
  endif
  if a:attr["bg"] != ""
    let gui .= " guibg=" . self.getguicolor(a:attr["bg"])
  endif
  if a:attr["sp"] != ""
    let gui .= " guisp=" . self.getguicolor(a:attr["sp"])
  endif
  let cui = printf(" cterm=%s", (attrs == []) ? "NONE" : join(attrs, ','))
  if a:attr["fg"] != ""
    let fg = self.getfg(a:attr)
    let cc = self.getctermcolor(fg)
    if cc != -1
      let cui .= " ctermfg=" . cc
    endif
  endif
  if a:attr["bg"] != ""
    let cc = self.getctermcolor(a:attr["bg"])
    if cc != -1
      let cui .= " ctermbg=" . cc
    endif
  endif
  if has("gui_running")
    return "hi " . a:attr["name"] . gui . cui
  else
    return "hi " . a:attr["name"] . cui . gui
  endif
endfunction

function hiedit.getfg(attr)
  let fg = a:attr["fg"]
  if &t_Co == 8 && a:attr["bold"] && index(self.palette, fg) < 8
    let fg = self.palette[index(self.palette, fg) + 8]
  endif
  return fg
endfunction

" vim/src/syntax.c:6940
let hiedit.stdcolorname = [
\"black", "darkblue", "darkgreen", "darkcyan",
\"darkred", "darkmagenta", "brown", "darkyellow",
\"gray", "grey",
\"lightgray", "lightgrey", "darkgray", "darkgrey",
\"blue", "lightblue", "green", "lightgreen",
\"cyan", "lightcyan", "red", "lightred", "magenta",
\"lightmagenta", "yellow", "lightyellow", "white"]

function hiedit.getguicolor(color)
  let name = self.getctermcolor(a:color)
  if index(self.stdcolorname, name) != -1
    return name
  endif
  if self.use_colorname
    return self.getcolorname(a:color)
  endif
  return a:color
endfunction

function hiedit.getctermcolor(color)
  let name = self.getcolorname(a:color)
  if index(self.stdcolorname, name) != -1
    return name
  endif
  return index(self.palette, a:color)
endfunction

function hiedit.getattr(name)
  let attr = {}
  let attr["name"] = a:name
  redir => str
  silent! execute "hi " . attr["name"]
  redir END
  let attr["cleared"] = (str =~ 'cleared')
  let link = matchstr(str, 'links to \zs\w\+')
  if link != "" && a:name != "Normal"
    let attr["link"] = link
    let attr["fg"] = ""
    let attr["bg"] = ""
    let attr["sp"] = ""
    let attr["bold"] = 0
    let attr["italic"] = 0
    let attr["reverse"] = 0
    let attr["underline"] = 0
    let attr["undercurl"] = 0
  else
    let id = hlID(a:name)
    let attr["link"] = ""
    if has("gui_running")
      let fg = synIDattr(id, "fg#")
      if fg == ""
        let fg = self.getcolorvalue(synIDattr(id, "fg"))
      endif
      let bg = synIDattr(id, "bg#")
      if bg == ""
        let bg = self.getcolorvalue(synIDattr(id, "bg"))
      endif
    else
      let fg = synIDattr(id, "fg")
      let fg = (fg == -1) ? "" : self.palette[fg]
      let bg = synIDattr(id, "bg")
      let bg = (bg == -1) ? "" : self.palette[bg]
    endif
    let attr["fg"] = fg
    let attr["bg"] = bg
    let attr["bold"] = synIDattr(id, "bold") + 0
    let attr["italic"] = synIDattr(id, "italic") + 0
    let attr["reverse"] = synIDattr(id, "reverse") + synIDattr(id, "inverse") + 0
    if attr["reverse"] == 2
      let attr["reverse"] = 1
    endif
    let attr["underline"] = synIDattr(id, "underline") + 0
    let attr["undercurl"] = synIDattr(id, "undercurl") + 0
    " XXX: synIDattr does not support guisp
    let sp = matchstr(str, 'guisp=\zs[#0-9A-Za-z_]\+')
    let attr["sp"] = self.getcolorvalue(sp)
  endif
  if !has_key(self.orig_attr, a:name)
    let self.orig_attr[a:name] = copy(attr)
  endif
  return attr
endfunction

function hiedit.setattr(attr)
  if a:attr["name"] == "Normal"
    let nattr = self.getattr("Normal")
    let bg = &background
  endif
  execute "hi clear " . a:attr["name"]
  execute self.make_hi_cmd(a:attr)
  if a:attr["name"] == "Normal" && a:attr["bg"] != nattr["bg"]
    if bg != &background
      call self.reset_screen()
    elseif a:attr["bg"] == ""
      set background&
      call self.reset_screen()
    elseif has('gui_running')
      " GVim does not change 'background'.
      "                  0123456789ABCDEF
      "         8 color: dllldlll
      " 16/88/256 color: dddddddldlllllll
      let s = "dddddddldlllllll"
      let n = index(self.palette, a:attr["bg"])
      if 0 <= n && n <= 15 && s[n] != &background[0]
        let &background = (&background == "dark") ? "light" : "dark"
      endif
      call self.reset_screen()
    endif
  endif
endfunction

" 16 color palette.
" this is different for each terminals.
let hiedit.palette_16 = [
\hiedit.color_name2val["black"],
\hiedit.color_name2val["darkred"],
\hiedit.color_name2val["darkgreen"],
\hiedit.color_name2val["darkyellow"],
\hiedit.color_name2val["darkblue"],
\hiedit.color_name2val["darkmagenta"],
\hiedit.color_name2val["darkcyan"],
\hiedit.color_name2val["lightgray"],
\hiedit.color_name2val["darkgray"],
\hiedit.color_name2val["red"],
\hiedit.color_name2val["green"],
\hiedit.color_name2val["yellow"],
\hiedit.color_name2val["blue"],
\hiedit.color_name2val["magenta"],
\hiedit.color_name2val["cyan"],
\hiedit.color_name2val["white"]]

" xterm 16
let hiedit.palette_xterm16 = [
\hiedit.color_name2val["black"],
\hiedit.color_name2val["red3"],
\hiedit.color_name2val["green3"],
\hiedit.color_name2val["yellow3"],
\hiedit.color_name2val["blue2"],
\hiedit.color_name2val["magenta3"],
\hiedit.color_name2val["cyan3"],
\hiedit.color_name2val["gray90"],
\hiedit.color_name2val["gray50"],
\hiedit.color_name2val["red"],
\hiedit.color_name2val["green"],
\hiedit.color_name2val["yellow"],
\"#5c5cff",
\hiedit.color_name2val["magenta"],
\hiedit.color_name2val["cyan"],
\hiedit.color_name2val["white"]]

" MS-DOS
let hiedit.palette_pc16 = [
\hiedit.color_name2val["black"],
\hiedit.color_name2val["darkblue"],
\hiedit.color_name2val["darkgreen"],
\hiedit.color_name2val["darkcyan"],
\hiedit.color_name2val["darkred"],
\hiedit.color_name2val["darkmagenta"],
\hiedit.color_name2val["brown"],
\hiedit.color_name2val["lightgray"],
\hiedit.color_name2val["darkgray"],
\hiedit.color_name2val["blue"],
\hiedit.color_name2val["green"],
\hiedit.color_name2val["cyan"],
\hiedit.color_name2val["red"],
\hiedit.color_name2val["magenta"],
\hiedit.color_name2val["yellow"],
\hiedit.color_name2val["white"]]

" xterm/256colres.h
let hiedit.palette_256 = [
\"#000000", "#00005f", "#000087", "#0000af", "#0000d7", "#0000ff",
\"#005f00", "#005f5f", "#005f87", "#005faf", "#005fd7", "#005fff",
\"#008700", "#00875f", "#008787", "#0087af", "#0087d7", "#0087ff",
\"#00af00", "#00af5f", "#00af87", "#00afaf", "#00afd7", "#00afff",
\"#00d700", "#00d75f", "#00d787", "#00d7af", "#00d7d7", "#00d7ff",
\"#00ff00", "#00ff5f", "#00ff87", "#00ffaf", "#00ffd7", "#00ffff",
\"#5f0000", "#5f005f", "#5f0087", "#5f00af", "#5f00d7", "#5f00ff",
\"#5f5f00", "#5f5f5f", "#5f5f87", "#5f5faf", "#5f5fd7", "#5f5fff",
\"#5f8700", "#5f875f", "#5f8787", "#5f87af", "#5f87d7", "#5f87ff",
\"#5faf00", "#5faf5f", "#5faf87", "#5fafaf", "#5fafd7", "#5fafff",
\"#5fd700", "#5fd75f", "#5fd787", "#5fd7af", "#5fd7d7", "#5fd7ff",
\"#5fff00", "#5fff5f", "#5fff87", "#5fffaf", "#5fffd7", "#5fffff",
\"#870000", "#87005f", "#870087", "#8700af", "#8700d7", "#8700ff",
\"#875f00", "#875f5f", "#875f87", "#875faf", "#875fd7", "#875fff",
\"#878700", "#87875f", "#878787", "#8787af", "#8787d7", "#8787ff",
\"#87af00", "#87af5f", "#87af87", "#87afaf", "#87afd7", "#87afff",
\"#87d700", "#87d75f", "#87d787", "#87d7af", "#87d7d7", "#87d7ff",
\"#87ff00", "#87ff5f", "#87ff87", "#87ffaf", "#87ffd7", "#87ffff",
\"#af0000", "#af005f", "#af0087", "#af00af", "#af00d7", "#af00ff",
\"#af5f00", "#af5f5f", "#af5f87", "#af5faf", "#af5fd7", "#af5fff",
\"#af8700", "#af875f", "#af8787", "#af87af", "#af87d7", "#af87ff",
\"#afaf00", "#afaf5f", "#afaf87", "#afafaf", "#afafd7", "#afafff",
\"#afd700", "#afd75f", "#afd787", "#afd7af", "#afd7d7", "#afd7ff",
\"#afff00", "#afff5f", "#afff87", "#afffaf", "#afffd7", "#afffff",
\"#d70000", "#d7005f", "#d70087", "#d700af", "#d700d7", "#d700ff",
\"#d75f00", "#d75f5f", "#d75f87", "#d75faf", "#d75fd7", "#d75fff",
\"#d78700", "#d7875f", "#d78787", "#d787af", "#d787d7", "#d787ff",
\"#d7af00", "#d7af5f", "#d7af87", "#d7afaf", "#d7afd7", "#d7afff",
\"#d7d700", "#d7d75f", "#d7d787", "#d7d7af", "#d7d7d7", "#d7d7ff",
\"#d7ff00", "#d7ff5f", "#d7ff87", "#d7ffaf", "#d7ffd7", "#d7ffff",
\"#ff0000", "#ff005f", "#ff0087", "#ff00af", "#ff00d7", "#ff00ff",
\"#ff5f00", "#ff5f5f", "#ff5f87", "#ff5faf", "#ff5fd7", "#ff5fff",
\"#ff8700", "#ff875f", "#ff8787", "#ff87af", "#ff87d7", "#ff87ff",
\"#ffaf00", "#ffaf5f", "#ffaf87", "#ffafaf", "#ffafd7", "#ffafff",
\"#ffd700", "#ffd75f", "#ffd787", "#ffd7af", "#ffd7d7", "#ffd7ff",
\"#ffff00", "#ffff5f", "#ffff87", "#ffffaf", "#ffffd7", "#ffffff",
\"#080808", "#121212", "#1c1c1c", "#262626", "#303030", "#3a3a3a",
\"#444444", "#4e4e4e", "#585858", "#626262", "#6c6c6c", "#767676",
\"#808080", "#8a8a8a", "#949494", "#9e9e9e", "#a8a8a8", "#b2b2b2",
\"#bcbcbc", "#c6c6c6", "#d0d0d0", "#dadada", "#e4e4e4", "#eeeeee"]

" xterm/88colres.h
let hiedit.palette_88 = [
\"#000000", "#00008b", "#0000cd", "#0000ff",
\"#008b00", "#008b8b", "#008bcd", "#008bff",
\"#00cd00", "#00cd8b", "#00cdcd", "#00cdff",
\"#00ff00", "#00ff8b", "#00ffcd", "#00ffff",
\"#8b0000", "#8b008b", "#8b00cd", "#8b00ff",
\"#8b8b00", "#8b8b8b", "#8b8bcd", "#8b8bff",
\"#8bcd00", "#8bcd8b", "#8bcdcd", "#8bcdff",
\"#8bff00", "#8bff8b", "#8bffcd", "#8bffff",
\"#cd0000", "#cd008b", "#cd00cd", "#cd00ff",
\"#cd8b00", "#cd8b8b", "#cd8bcd", "#cd8bff",
\"#cdcd00", "#cdcd8b", "#cdcdcd", "#cdcdff",
\"#cdff00", "#cdff8b", "#cdffcd", "#cdffff",
\"#ff0000", "#ff008b", "#ff00cd", "#ff00ff",
\"#ff8b00", "#ff8b8b", "#ff8bcd", "#ff8bff",
\"#ffcd00", "#ffcd8b", "#ffcdcd", "#ffcdff",
\"#ffff00", "#ffff8b", "#ffffcd", "#ffffff",
\"#2e2e2e", "#5c5c5c", "#737373", "#8b8b8b",
\"#a2a2a2", "#b9b9b9", "#d0d0d0", "#e7e7e7"]

if &t_Co == 88
  let hiedit.palette = hiedit.palette_16 + hiedit.palette_88
else
  let hiedit.palette = hiedit.palette_16 + hiedit.palette_256
endif

function hiedit.reset_screen()
  call self.update_form()

  hi x_none guifg=black guibg=white ctermfg=0 ctermbg=7
  hi p_pick_fg guifg=#FFFFFF guibg=#FFFFFF ctermfg=7 ctermbg=7
  hi p_pick_bg guifg=#FFFFFF guibg=#FFFFFF ctermfg=7 ctermbg=7
  hi p_pick_sp guifg=#FFFFFF guibg=#FFFFFF ctermfg=7 ctermbg=7
  hi p_cur_fg guifg=#FFFFFF guibg=#FFFFFF  ctermfg=7 ctermbg=7
  hi p_cur_bg guifg=#FFFFFF guibg=#FFFFFF  ctermfg=7 ctermbg=7
  hi p_cur_sp guifg=#FFFFFF guibg=#FFFFFF  ctermfg=7 ctermbg=7

  let [row_off, col_off] = [2, 1]
  for i in range(has('gui_running') ? len(self.palette) : max([16, &t_Co]))
    if i < 16
      let [row, col] = [0, i]
    elseif 231 < i
      let [row, col] = [0, i - 216]
    else
      let [row, col] = [(i + 20) / 36, (i + 20) % 36]
    endif
    let color = self.getcolorvalue(self.palette[i])
    if &t_Co == 8 && i > 7
      execute printf("hi p_%d guifg=%s guibg=%s cterm=bold ctermfg=%d ctermbg=%d", i, color, color, i - 8,  i - 8)
    else
      execute printf("hi p_%d guifg=%s guibg=%s ctermfg=%d ctermbg=%d", i, color, color, (i == 7) ? 0 : 7, i)
    endif
  endfor

  if has('gui_running')
    for i in range(self.lu_num)
      execute printf("hi c_%d guifg=#FFFFFF guibg=#FFFFFF", i)
    endfor
    call self.update_luminance("#000000")
  endif
endfunction

function hiedit.create_sample_window()
  new --SAMPLE--
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nowrap
  setlocal nolist
  let &l:statusline = '%f   [left(1):select] [middle(2):clone] [right(3):pick-color]'

  put ='Normal NonText VertSplit LineNr SpecialKey Directory Title                    '
  put ='Cursor lCursor CursorIM CursorColumn CursorLine MatchParen                    '
  put ='DiffAdd DiffChange DiffDelete DiffText Folded FoldColumn SignColumn           '
  put ='Search IncSearch Visual VisualNOS ModeMsg MoreMsg WarningMsg ErrorMsg Question'
  put ='Pmenu PmenuSel PmenuSbar PmenuThumb SpellBad SpellCap SpellLocal SpellRare    '
  put ='StatusLine StatusLineNC WildMenu TabLine TabLineFill TabLineSel               '
  put ='Comment Special Identifier Underlined Ignore Error Todo                       '
  put ='Constant Statement Type PreProc                                               '
  put ='User1 User2 User3 User4 User5 User6 User7 User8 User9                         '
  put ='--- not recognized when ''advance'' is off -------------------------------------'
  put ='String Character Number Boolean Float Function                                '
  put ='Conditional Repeat Label Operator Keyword StorageClass Structure Typedef      '
  put ='Include Define Macro PreCondit                                 Exception      '
  put ='Tag SpecialChar Delimiter SpecialComment Debug                                '
  put ='--- SAMPLE SCREEN ------------------------------------------------------------'
  1delete _

  call append('$', [
     \ ' [No Name]  [tab2]  [tab3]                X       1                           ',
     \ '  1 sample text$  |                           >>  2 signed line               ',
     \ '  2 >---<Tab>$    |+ +--23 lines: 1. One---       3                           ',
     \ '  3 $             |                           [sign]                          ',
     \ '~                 |- 2. Two                   The quick brown fox             ',
     \ '~                 ||   open fold              jumps over the lazy dog         ',
     \ '~                 ||                          [search]                        ',
     \ '[No Name]          test.txt                   /fox                            ',
     \ 'Sample text (for Visual select).                                              ',
     \ '~                                             E486: Pattern not found: Word   ',
     \ '[No Name]                                     -- More --                      ',
     \ '-- VISUAL --                    15            Press ENTER or type command to continue',
     \ '                                                                              ',
     \ '  1 popup                                                                     ',
     \ '~   pop                                                                       ',
     \ '~   popup                                                                     ',
     \ '~   ppop                                                                      ',
     \ '                                                                              ',
     \ ])

  for name in self.hlname_basic + self.hlname_advance
    execute printf("syntax keyword hlid_%s %s", name, name)
    execute printf("hi link hlid_%s %s", name, name)
  endfor

  let color = [
     \ 'FFFFFFFFFFFDDDDDDDDDDDDDDDDEEEEEEEEEEEEEEED   002222                          ',
     \ '2222           6  -//                           2222<<<<<<<<<<<<<<<<<<<<<<<<<<',
     \ '2222====     6    -//......................   002222                          ',
     \ '22226             -//                         CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
     \ '666666666666666666-//                         <<<             111             ',
     \ '666666666666666666-//                                    <<<                  ',
     \ '666666666666666666-//                         BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
     \ 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC       !                           ',
     \ '            !HHHHHHHHHHHHHH   3                                               ',
     \ '6666666666666666666666666666666666666666666   ,,,,,,,,,,,,,,,,,,,,,,,,,,,,,   ',
     \ 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB   5555555555                      ',
     \ '444444444444                                  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;',
     \ '                                                                              ',
     \ '2222     !                                                                    ',
     \ '6666777777777777777966666666666666666666666                                   ',
     \ '6666888888888888888966666666666666666666666                                   ',
     \ '6666777777777777777:66666666666666666666666                                   ',
     \ '                                                                              ',
     \ ]

  let id2name = {
        \ " ": "Normal",
        \ "!": "Cursor",
        \ "#": "CursorIM",
        \ "$": "CursorColumn",
        \ "%": "CursorLine",
        \ "&": "Directory",
        \ "(": "DiffAdd",
        \ ")": "DiffChange",
        \ "*": "DiffDelete",
        \ "+": "DiffText",
        \ ",": "ErrorMsg",
        \ "-": "VertSplit",
        \ ".": "Folded",
        \ "/": "FoldColumn",
        \ "0": "SignColumn",
        \ "1": "IncSearch",
        \ "2": "LineNr",
        \ "3": "MatchParen",
        \ "4": "ModeMsg",
        \ "5": "MoreMsg",
        \ "6": "NonText",
        \ "7": "Pmenu",
        \ "8": "PmenuSel",
        \ "9": "PmenuSbar",
        \ ":": "PmenuThumb",
        \ ";": "Question",
        \ "<": "Search",
        \ "=": "SpecialKey",
        \ ">": "SpellBad",
        \ "?": "SpellCap",
        \ "@": "SpellLocal",
        \ "A": "SpellRare",
        \ "B": "StatusLine",
        \ "C": "StatusLineNC",
        \ "D": "TabLine",
        \ "E": "TabLineFill",
        \ "F": "TabLineSel",
        \ "G": "Title",
        \ "H": "Visual",
        \ "I": "VisualNOS",
        \ "J": "WarningMsg",
        \ "K": "WildMenu",
        \ "L": "Comment",
        \ "M": "Constant",
        \ "N": "Special",
        \ "O": "Identifier",
        \ "P": "Statement",
        \ "Q": "PreProc",
        \ "R": "Type",
        \ "S": "Underlined",
        \ "T": "Ignore",
        \ "U": "Error",
        \ "V": "Todo",
        \ "W": "String",
        \ "X": "Character",
        \ "Y": "Number",
        \ "Z": "Boolean",
        \ "[": "Float",
        \ "]": "Function",
        \ "^": "Conditional",
        \ "_": "Repeat",
        \ "`": "Label",
        \ "a": "Operator",
        \ "b": "Keyword",
        \ "c": "Exception",
        \ "d": "Include",
        \ "e": "Define",
        \ "f": "Macro",
        \ "g": "PreCondit",
        \ "h": "StorageClass",
        \ "i": "Structure",
        \ "j": "Typedef",
        \ "k": "Tag",
        \ "l": "SpecialChar",
        \ "m": "Delimiter",
        \ "n": "SpecialComment",
        \ "o": "Debug",
        \ "p": "lCursor",
        \ "q": "User1",
        \ "r": "User2",
        \ "s": "User3",
        \ "t": "User4",
        \ "u": "User5",
        \ "v": "User6",
        \ "w": "User7",
        \ "x": "User8",
        \ "y": "User9",
        \ }

  let [row_off, col_off] = [16, 1]
  for row in range(len(color))
    for col in range(len(color[row]))
      if color[row][col] != " "
        let name = id2name[color[row][col]]
        execute printf('syntax match hlid_%s /\%%%dl\%%%dc./', name, row_off + row, col_off + col)
        execute printf('hi link hlid_%s %s', name, name)
      endif
    endfor
  endfor
endfunction

function hiedit.init()
  rightbelow new --EDITOR--
  if has('gui_running') || &t_Co > 88
    12wincmd _
  elseif &t_Co == 88
    8wincmd _
  else
    6wincmd _
  endif
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal nowrap
  setlocal nolist
  setlocal winfixheight
  let &l:statusline = '%f   [left(1):fg] [middle(2):sp] [right(3):bg]'

  if has('gui_running') || &t_Co > 88
    call setline(1, repeat([repeat(" ", 36 + self.lu_num)], 12))
  elseif &t_Co == 88
    call setline(1, repeat([repeat(" ", 36 + self.lu_num)], 8))
  elseif &t_Co == 8
    call setline(1, repeat([repeat(" ", 36 + self.lu_num)], 6))
    call setline(2, "0123456789ABCDEF (8-F is bold color, fg only)                 XXXXXX")
  else
    call setline(1, repeat([repeat(" ", 36 + self.lu_num)], 6))
    call setline(2, "0123456789ABCDEF                                              XXXXXX")
  endif

  syntax match x_none /./

  syntax match p_pick_fg /\%2l\%63c./
  syntax match p_pick_bg /\%2l\%64c./
  syntax match p_pick_sp /\%2l\%65c./
  syntax match p_cur_fg /\%2l\%66c./
  syntax match p_cur_bg /\%2l\%67c./
  syntax match p_cur_sp /\%2l\%68c./
  let [row_off, col_off] = [2, 1]
  for i in range(has('gui_running') ? len(self.palette) : max([16, &t_Co]))
    if &t_Co == 88
      if i < 16
        let [row, col] = [0, i]
      elseif 79 < i
        let [row, col] = [0, i - 64]
      else
        let [row, col] = [(i + 16) / 32, (i + 16) % 32]
      endif
    else
      if i < 16
        let [row, col] = [0, i]
      elseif 231 < i
        let [row, col] = [0, i - 216]
      else
        let [row, col] = [(i + 20) / 36, (i + 20) % 36]
      endif
    endif
    execute printf('syntax match p_%d /\%%%dl\%%%dc./', i, row_off + row, col_off + col)
  endfor
  if has('gui_running')
    let [row_off, col_off] = [3, 37]
    for i in range(self.lu_num)
      execute printf("hi c_%d guifg=#FFFFFF guibg=#FFFFFF", i)
      execute printf("hi w_%d guifg=#FFFFFF guibg=#FFFFFF", i)
      execute printf("hi k_%d guifg=#FFFFFF guibg=#FFFFFF", i)
      execute printf("hi r_%d guifg=#FFFFFF guibg=#FFFFFF", i)
      execute printf("hi g_%d guifg=#FFFFFF guibg=#FFFFFF", i)
      execute printf("hi b_%d guifg=#FFFFFF guibg=#FFFFFF", i)
      execute printf('syntax match c_%d /\%%%dl\%%%dc./', i, row_off + 0, col_off + i)
      execute printf('syntax match w_%d /\%%%dl\%%%dc./', i, row_off + 1, col_off + i)
      execute printf('syntax match k_%d /\%%%dl\%%%dc./', i, row_off + 2, col_off + i)
      execute printf('syntax match r_%d /\%%%dl\%%%dc./', i, row_off + 3, col_off + i)
      execute printf('syntax match g_%d /\%%%dl\%%%dc./', i, row_off + 4, col_off + i)
      execute printf('syntax match b_%d /\%%%dl\%%%dc./', i, row_off + 5, col_off + i)
    endfor
  endif

  let self.attr = self.getattr("Normal")
  call self.reset_screen()
endfunction

call hiedit.init()

let &cpo = s:save_cpo
