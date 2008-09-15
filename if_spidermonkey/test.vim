let arr = [1, 2, 3, 4, 5]
let dict = {'a':'aaa', 'b':'bbb', 'c':'ccc'}

let if_spidermonkey = './if_spidermonkey.so'
echo libcall(if_spidermonkey, 'init', if_spidermonkey)
echo libcall(if_spidermonkey, 'execute', 'load("test.js")')
