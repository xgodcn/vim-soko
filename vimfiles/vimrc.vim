let &runtimepath = join(split(&rtp, ',') + split(globpath(&rtp, 'package/*/'), '\n'), ',')
set encoding=utf-8
set termencoding=default
set fileencodings=ucs-bom,utf-8,euc-jp,cp932
set ambiwidth=double
let &backupdir = fnamemodify(finddir('backup', &runtimepath), ':p')
let &directory = fnamemodify(finddir('swapfile', &runtimepath), ':p')
let &backup = isdirectory(&backupdir)
let &writebackup = isdirectory(&backupdir)
let &swapfile = isdirectory(&directory)
set history=100               " keep 100 lines of command line history
set ignorecase smartcase
set incsearch                 " do incremental searching
set hlsearch
set grepprg=internal
set list listchars=tab:>-,trail:-
set showcmd
set cmdheight=2
set laststatus=2
set wildmenu
set statusline=%f\ %m%r%y%{_bomb()}%{_fenc()}%{_ff()}%#Error#%{_qf()}%{_loc()}%*%=%v\ %l/%L
set winminheight=0
set noequalalways
set backspace=indent,eol,start
set textwidth=72
set formatoptions+=nmB fo-=t fo-=c
set autoindent
set shiftwidth=2 softtabstop=2 expandtab
set cinoptions=t0,:0,g0
set tags+=./tags;
set guioptions-=t             " disable tearoff menu
set iminsert=0 imsearch=0     " turn off IM in default
set mouse=nvi
set mousemodel=popup

function _bomb()
  return &bomb ? '[bomb]' : ''
endfunction

function _fenc()
  return '[' . ((&fenc == '') ? &enc : &fenc) . ']'
endfunction

function _ff()
  return '[' . &ff . ']'
endfunction

function _qf()
  let n = len(getqflist())
  if n == 0
    return ''
  endif
  return '[G:' . n . ']'
endfunction

function _loc()
  let n = len(getloclist(0))
  if n == 0
    return ''
  endif
  return '[L:' . n . ']'
endfunction

function s:ExpandTab()
  setl expandtab!
  return ""
endfunction

function s:Number(first, last, reg, bang)
  if a:bang == ""
    let list_save = &l:list
    setl nolist
  endif
  redir => str
  execute printf("%d,%dnumber", a:first, a:last)
  redir END
  if a:bang == ""
    let &l:list = list_save
  endif
  let str = substitute(str, '^\n\|\s\+\ze\n', '', 'g')
  call setreg(a:reg, str, "V")
endfunction

function s:MinWindow(threshold)
  " don't close completion preview window
  if mode() == 'n' && winheight(winnr('#')) <= a:threshold
    execute winnr('#') . 'resize 0'
  endif
endfunction

function s:Lint()
  let cmd = 'compiler %s | exe "silent lmake!" | let loc += getloclist(0)'
  let loc = []
  if &ft == 'c'
    if executable('splint')
      execute printf(cmd, 'splint')
    endif
  elseif &ft == 'php'
    if executable('php')
      execute printf(cmd, 'php')
    endif
    if executable('phpmd')
      execute printf(cmd, 'phpmd')
    endif
  elseif &ft == 'python'
    if executable('pylint')
      execute printf(cmd, 'pylint')
    endif
    if executable('pyflakes')
      execute printf(cmd, 'pyflakes')
    endif
    if executable('pep8')
      execute printf(cmd, 'pep8')
    endif
  endif
  redraw!
  call setloclist(0, loc)
endfunction

function! s:Abbrev(src)
  for [cond, pat, expr] in s:abbrev
    if eval(cond)
      let _ = matchlist(a:src, pat)
      if !empty(_)
        return repeat("\<BS>", len(_[0])) . eval(expr)
      endif
    endif
  endfor
  return ''
endfunction

function! s:AbbrevFileDir()
  let sep = has('win32') ? '\' : '/'
  let dir = expand('%:h') . sep
  if mode() == 'c'
    let dir = escape(dir, ' ')
  endif
  return dir
endfunction

function! _AbbrevFile()
  let src = strpart(getline('.'), 0, col('.') - 1)
  let sep = has('win32') ? '\' : '/'
  for i in range(len(src))
    if src[i - 1] !~ '\f' && isdirectory(src[i : ])
      let path = src[i : ]
      break
    endif
  endfor
  if exists('path')
    let lst = split(glob(substitute(path, '[\\/]*$', '/*', '')), '\n')
    let lst = map(lst, 'isdirectory(v:val) ? v:val . sep : v:val')
    call complete(col('.') - len(path), lst)
  endif
  return ''
endfunction

let s:abbrev = [
      \ ['mode() =~ "[ic]"', '\<date$', 'strftime("%Y-%m-%d")'],
      \ ['mode() =~ "[ic]"', '\<time$', 'strftime("%H:%S:%M")'],
      \ ['mode() =~ "[ic]"', '\<dir$', 's:AbbrevFileDir()'],
      \ ['mode() =~ "[i]"', '\ze[\\/]$', '"\<C-R>=_AbbrevFile()\<CR>"'],
      \ ]

inoremap <expr> <C-]> <SID>Abbrev(strpart(getline('.'), 0, col('.') - 1))
cnoremap <expr> <C-]> <SID>Abbrev(strpart(getcmdline(), 0, getcmdpos() - 1))

xnoremap * "9y/<C-R>='\V'.substitute(escape(@9,'\/'),'\n','\\n','g')<CR><CR>
inoremap <script> <S-Tab> <SID>ExpandTab<Tab><SID>ExpandTab
inoremap <expr> <SID>ExpandTab <SID>ExpandTab()
nmap mm <Plug>MarkerToggle
xmap m  <Plug>MarkerToggle

nnoremap K <Nop>
xnoremap K <Nop>

command! -range -register -bang Number call s:Number(<line1>, <line2>, "<reg>", "<bang>")

augroup vimrcEx
  au!

  " When editing a file, always jump to the last known cursor position.
  " Don't do it when the position is invalid or when inside an event handler
  " (happens when dropping a file on gvim).
  " Also don't do it when the mark is in the first line, that is the default
  " position when opening a file.
  autocmd BufReadPost *
        \ if line("'\"") > 1 && line("'\"") <= line("$") |
        \   exe "normal! g`\"" |
        \ endif

  " shut up beep.  t_vb should be set after GUI init
  autocmd VimEnter * set visualbell t_vb=
  " highlight for Input Method mode
  autocmd ColorScheme * hi CursorIM guibg=purple
  " weaken special chars
  autocmd ColorScheme * hi SpecialKey guifg=gray
  " minimize window
  autocmd WinEnter * call s:MinWindow(3)
  " close completion preview window
  autocmd InsertLeave,CursorMovedI * if pumvisible() == 0 | pclose | endif
  " lint
  autocmd BufWritePost * call s:Lint()
  " don't copy location list
  autocmd VimEnter,WinEnter *
        \   if !exists('w:_init')
        \ |   let w:_init = 1
        \ |   lexpr []
        \ | endif
augroup END

augroup filetypeplugin
  autocmd FileType * setl sw< sts< ts< et< tw< fo<
augroup END

colorscheme delek
syntax on
filetype plugin indent on

augroup filetypeplugin
  autocmd FileType c,cpp,java,python,php,perl setl sw=4 sts=4 et
augroup END

augroup filetypeindent
  autocmd FileType html,xhtml,xml,java setl indentexpr=
  autocmd FileType php setl autoindent indentkeys-==<?
  autocmd FileType javascript setl nocindent smartindent
augroup END

augroup syntax
augroup END

let g:php_noShortTags = 1

runtime macros/matchit.vim
