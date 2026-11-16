import Foundation

// 由 scripts/practice/gen_practice.py 生成（双拼调研 P3-11），别手改。
// 基础：每个音节一个最常用的字（频率来自 Rime 八股文 essay，转成简体），再补到常用字；词组：常用两三字词；短句：纠错语料按标点切的短句。
// 拼音用 pypinyin 标（ü 写 v，j q x y 后写 u），只留音节表里有的。每行「字词<TAB>空格分开的全拼」。
enum DoublePinyinPracticeData {
    static let basic = """
的	de
了	le
我	wo
是	shi
在	zai
你	ni
和	he
有	you
不	bu
就	jiu
都	dou
也	ye
要	yao
吧	ba
好	hao
他	ta
说	shuo
去	qu
到	dao
没	mei
还	hai
上	shang
对	dui
那	na
人	ren
个	ge
看	kan
中	zhong
呢	ne
来	lai
吗	ma
为	wei
会	hui
与	yu
给	gei
等	deng
这	zhe
用	yong
下	xia
恩	en
能	neng
很	hen
多	duo
做	zuo
想	xiang
点	dian
被	bei
后	hou
地	di
而	er
一	yi
从	cong
将	jiang
但	dan
么	me
过	guo
打	da
年	nian
啦	la
买	mai
里	li
让	rang
小	xiao
先	xian
啊	a
或	huo
并	bing
呀	ya
找	zhao
新	xin
及	ji
跟	gen
太	tai
才	cai
发	fa
日	ri
可	ke
比	bi
玩	wan
们	men
最	zui
吃	chi
月	yue
真	zhen
其	qi
话	hua
出	chu
请	qing
钱	qian
叫	jiao
开	kai
谁	shui
当	dang
哈	ha
家	jia
问	wen
之	zhi
别	bie
更	geng
该	gai
走	zou
快	kuai
高	gao
您	nin
所	suo
天	tian
却	que
内	nei
写	xie
啥	sha
老	lao
行	xing
带	dai
如	ru
死	si
晕	yun
刚	gang
成	cheng
无	wu
换	huan
爱	ai
听	ting
少	shao
元	yuan
卡	ka
靠	kao
帮	bang
算	suan
忙	mang
学	xue
系	xi
分	fen
总	zong
则	ze
张	zhang
三	san
见	jian
连	lian
车	che
放	fang
全	quan
按	an
早	zao
弄	nong
干	gan
本	ben
偶	ou
进	jin
同	tong
怕	pa
女	nv
组	zu
错	cuo
住	zhu
名	ming
跑	pao
网	wang
次	ci
装	zhuang
哦	o
图	tu
掉	diao
路	lu
正	zheng
强	qiang
外	wai
头	tou
应	ying
生	sheng
因	yin
子	zi
类	lei
送	song
书	shu
表	biao
乖	guai
拍	pai
撒	sa
接	jie
办	ban
非	fei
差	cha
周	zhou
副	fu
收	shou
男	nan
两	liang
股	gu
转	zhuan
便	bian
黄	huang
米	mi
聊	liao
哇	wa
包	bao
白	bai
够	gou
管	guan
定	ding
样	yang
面	mian
传	chuan
据	ju
群	qun
黑	hei
慢	man
刷	shua
贵	gui
选	xuan
站	zhan
牛	niu
谈	tan
曾	ceng
经	jing
汗	han
陈	chen
红	hong
楼	lou
挂	gua
读	du
某	mou
条	tiao
乱	luan
热	re
光	guang
风	feng
咋	za
且	qie
林	lin
额	e
刘	liu
若	ruo
饭	fan
村	cun
空	kong
山	shan
毛	mao
另	ling
贴	tie
盘	pan
坏	huai
爽	shuang
片	pian
岁	sui
龙	long
共	gong
超	chao
均	jun
冲	chong
动	dong
特	te
神	shen
鸟	niao
梦	meng
陪	pei
哭	ku
口	kou
球	qiu
仍	reng
跌	die
提	ti
票	piao
咩	mie
段	duan
平	ping
抓	zhua
套	tao
草	cao
罗	luo
唱	chang
蓝	lan
团	tuan
色	se
哟	yo
混	hun
退	tui
破	po
修	xiu
亲	qin
款	kuan
率	lv
胡	hu
烟	yan
木	mu
肉	rou
需	xu
论	lun
噶	ga
列	lie
冷	leng
帅	shuai
奥	ao
俩	lia
追	zhui
丢	diu
孙	sun
咱	zan
宁	ning
波	bo
亏	kui
苏	su
准	zhun
春	chun
秒	miao
吹	chui
皮	pi
汤	tang
民	min
品	pin
抽	chou
托	tuo
卷	juan
床	chuang
胖	pang
困	kun
莫	mo
闹	nao
桥	qiao
穷	qiong
然	ran
疼	teng
狼	lang
狂	kuang
捏	nie
赛	sai
哼	heng
抗	kang
贼	zei
滚	gun
否	fou
设	she
熊	xiong
乃	nai
觉	jue
搜	sou
娘	niang
惨	can
诶	ei
软	ruan
荣	rong
测	ce
晒	shai
顺	shun
囧	jiong
碰	peng
擦	ca
藏	cang
产	chan
扎	zha
增	zeng
肯	ken
怒	nu
嫩	nen
拆	chai
脏	zang
瑞	rui
催	cui
寻	xun
钻	zuan
普	pu
吨	dun
诺	nuo
夸	kua
粗	cu
森	sen
喷	pen
略	lve
扫	sao
凑	cou
怎	zen
绕	rao
坑	keng
尊	zun
斌	bin
暖	nuan
润	run
昂	ang
桑	sang
卓	zhuo
航	hang
摘	zhai
拽	zhuai
翁	weng
泵	beng
囊	nang
僧	seng
吞	tun
掐	qia
虐	nve
扩	kuo
戳	chuo
窜	cuan
踹	chuai
栓	shuan
撇	pie
岑	cen
剖	pou
扽	den
谬	miu
鞥	eng
耨	nou
她	ta
把	ba
又	you
再	zai
时	shi
大	da
以	yi
着	zhe
得	de
于	yu
号	hao
嘛	ma
它	ta
向	xiang
前	qian
由	you
加	jia
已	yi
搞	gao
事	shi
拿	na
只	zhi
卖	mai
像	xiang
使	shi
回	hui
哪	na
者	zhe
起	qi
各	ge
咯	ge
水	shui
改	gai
唉	ai
万	wan
机	ji
区	qu
拉	la
页	ye
性	xing
第	di
完	wan
花	hua
长	zhang
讲	jiang
杀	sha
些	xie
睡	shui
挺	ting
王	wang
二	er
心	xin
作	zuo
每	mei
法	fa
市	shi
至	zhi
美	mei
线	xian
未	wei
级	ji
即	ji
哎	ai
此	ci
版	ban
俺	an
字	zi
考	kao
块	kuai
猪	zhu
手	shou
道	dao
座	zuo
儿	er
取	qu
低	di
难	nan
台	tai
受	shou
阿	a
喝	he
金	jin
四	si
近	jin
门	men
交	jiao
李	li
笑	xiao
自	zi
边	bian
型	xing
穿	chuan
越	yue
位	wei
部	bu
称	cheng
处	chu
累	lei
怪	guai
省	sheng
倒	dao
数	shu
查	cha
变	bian
象	xiang
半	ban
种	zhong
格	ge
五	wu
方	fang
顶	ding
唔	wu
马	ma
远	yuan
单	dan
海	hai
相	xiang
满	man
化	hua
班	ban
滴	di
关	guan
涨	zhang
店	dian
安	an
坐	zuo
约	yue
飞	fei
度	du
俄	e
歌	ge
报	bao
信	xin
占	zhan
原	yuan
文	wen
晚	wan
量	liang
式	shi
赚	zhuan
重	zhong
主	zhu
间	jian
入	ru
伐	fa
血	xue
队	dui
杨	yang
往	wang
达	da
国	guo
狗	gou
教	jiao
费	fei
离	li
西	xi
明	ming
妈	ma
期	qi
照	zhao
切	qie
留	liu
气	qi
画	hua
镇	zhen
哥	ge
甘	gan
云	yun
蛮	man
鱼	yu
骂	ma
值	zhi
既	ji
力	li
建	jian
洗	xi
懂	dong
双	shuang
指	zhi
东	dong
活	huo
练	lian
亿	yi
猫	mao
清	qing
药	yao
除	chu
通	tong
酒	jiu
饿	e
六	liu
病	bing
假	jia
久	jiu
课	ke
急	ji
城	cheng
任	ren
升	sheng
理	li
令	ling
克	ke
局	ju
雨	yu
货	huo
左	zuo
县	xian
常	chang
抢	qiang
菜	cai
恶	e
沈	shen
集	ji
感	gan
较	jiao
房	fang
敢	gan
火	huo
脸	lian
操	cao
南	nan
件	jian
吴	wu
声	sheng
叶	ye
德	de
雪	xue
噢	o
傻	sha
整	zheng
华	hua
呃	e
喊	han
现	xian
跳	tiao
养	yang
补	bu
合	he
反	fan
乐	le
篇	pian
待	dai
砸	za
深	shen
烦	fan
根	gen
求	qiu
投	tou
电	dian
厂	chang
知	zhi
八	ba
配	pei
器	qi
何	he
调	diao
鬼	gui
试	shi
谢	xie
仅	jin
层	ceng
北	bei
价	jia
份	fen
记	ji
赵	zhao
情	qing
七	qi
喂	wei
流	liu
招	zhao
须	xu
朱	zhu
痛	tong
石	shi
香	xiang
封	feng
眼	yan
易	yi
借	jie
派	pai
付	fu
十	shi
阳	yang
树	shu
游	you
油	you
排	pai
停	ting
军	jun
身	shen
章	zhang
科	ke
权	quan
星	xing
牌	pai
翻	fan
随	sui
场	chang
帖	tie
商	shang
库	ku
制	zhi
体	ti
板	ban
脚	jiao
物	wu
泡	pao
宝	bao
玉	yu
欲	yu
伤	shang
背	bei
尽	jin
剑	jian
解	jie
室	shi
证	zheng
底	di
业	ye
代	dai
呆	dai
亦	yi
布	bu
旧	jiu
工	gong
余	yu
词	ci
刀	dao
喔	o
铁	tie
千	qian
推	tui
落	luo
节	jie
轻	qing
笨	ben
九	jiu
输	shu
极	ji
江	jiang
短	duan
含	han
炒	chao
藉	ji
钟	zhong
丫	ya
徐	xu
签	qian
骗	pian
青	qing
耍	shua
夜	ye
许	xu
咁	gan
念	nian
党	dang
师	shi
土	tu
赢	ying
姐	jie
直	zhi
公	gong
秀	xiu
苦	ku
博	bo
鸡	ji
朝	chao
君	jun
诗	shi
烂	lan
梁	liang
静	jing
利	li
扣	kou
立	li
素	su
存	cun
烧	shao
断	duan
吾	wu
命	ming
睇	di
忘	wang
佛	fu
茶	cha
冰	bing
供	gong
案	an
田	tian
初	chu
造	zao
奖	jiang
抱	bao
野	ye
绿	lv
项	xiang
折	zhe
紧	jin
故	gu
服	fu
松	song
百	bai
兵	bing
英	ying
般	ban
演	yan
嘴	zui
填	tian
果	guo
获	huo
保	bao
唐	tang
夏	xia
硬	ying
寒	han
灯	deng
挖	wa
凡	fan
言	yan
题	ti
街	jie
防	fang
广	guang
距	ju
挑	tiao
纯	chun
竟	jing
源	yuan
官	guan
戏	xi
寄	ji
古	gu
首	shou
思	si
删	shan
郭	guo
亮	liang
秋	qiu
属	shu
胜	sheng
粉	fen
爆	bao
韩	han
戴	dai
雷	lei
盖	gai
港	gang
租	zu
众	zhong
兰	lan
志	zhi
赞	zan
引	yin
压	ya
亚	ya
齐	qi
员	yuan
食	shi
船	chuan
今	jin
恨	hen
愿	yuan
宋	song
银	yin
峰	feng
猛	meng
采	cai
客	ke
虽	sui
友	you
码	ma
领	ling
句	ju
"""

    static let words = """
一个	yi ge
没有	mei you
我们	wo men
可以	ke yi
什么	shen me
这个	zhe ge
呵呵	he he
现在	xian zai
自己	zi ji
就是	jiu shi
不是	bu shi
怎么	zen me
还是	hai shi
他们	ta men
如果	ru guo
知道	zhi dao
时候	shi hou
问题	wen ti
这样	zhe yang
已经	yi jing
哈哈	ha ha
因为	yin wei
公司	gong si
那个	na ge
今天	jin tian
工作	gong zuo
中国	zhong guo
但是	dan shi
不过	bu guo
可能	ke neng
应该	ying gai
所以	suo yi
你们	ni men
一下	yi xia
时间	shi jian
都是	dou shi
还有	hai you
进行	jin xing
觉得	jue de
需要	xu yao
不能	bu neng
开始	kai shi
东西	dong xi
那么	na me
这么	zhe me
喜欢	xi huan
比较	bi jiao
然后	ran hou
一些	yi xie
不会	bu hui
大家	da jia
很多	hen duo
看到	kan dao
不要	bu yao
一样	yi yang
这些	zhe xie
也是	ye shi
感觉	gan jue
看看	kan kan
其实	qi shi
出来	chu lai
好像	hao xiang
朋友	peng you
只是	zhi shi
明天	ming tian
以后	yi hou
这里	zhe li
而且	er qie
系统	xi tong
通过	tong guo
一定	yi ding
使用	shi yong
一起	yi qi
企业	qi ye
或者	huo zhe
市场	shi chang
发展	fa zhan
一直	yi zhi
北京	bei jing
其他	qi ta
产品	chan pin
这种	zhe zhong
事情	shi qing
的人	de ren
为什么	wei shen me
发现	fa xian
希望	xi wang
地方	di fang
只有	zhi you
情况	qing kuang
要求	yao qiu
电话	dian hua
信息	xin xi
多少	duo shao
提供	ti gong
一般	yi ban
谢谢	xie xie
回来	hui lai
主要	zhu yao
生活	sheng huo
不错	bu cuo
上海	shang hai
目前	mu qian
直接	zhi jie
所有	suo you
晚上	wan shang
技术	ji shu
方面	fang mian
出现	chu xian
虽然	sui ran
支持	zhi chi
为了	wei le
价格	jia ge
美国	mei guo
是不是	shi bu shi
我的	wo de
选择	xuan ze
以前	yi qian
项目	xiang mu
非常	fei chang
里面	li mian
别人	bie ren
国家	guo jia
你的	ni de
以及	yi ji
同时	tong shi
对于	dui yu
两个	liang ge
准备	zhun bei
管理	guan li
一点	yi dian
肯定	ken ding
这是	zhe shi
服务	fu wu
认为	ren wei
昨天	zuo tian
最后	zui hou
成为	cheng wei
网站	wang zhan
起来	qi lai
作为	zuo wei
哪里	na li
之后	zhi hou
手机	shou ji
继续	ji xu
真的	zhen de
不同	bu tong
用户	yong hu
由于	you yu
结果	jie guo
估计	gu ji
最近	zui jin
影响	ying xiang
学校	xue xiao
孩子	hai zi
好的	hao de
设计	she ji
任务	ren wu
关系	guan xi
部分	bu fen
活动	huo dong
必须	bi xu
网络	wang luo
研究	yan jiu
如何	ru he
当然	dang ran
那些	na xie
功能	gong neng
可是	ke shi
学生	xue sheng
数据	shu ju
方式	fang shi
告诉	gao su
给我	gei wo
内容	nei rong
一次	yi ci
那里	na li
女人	nv ren
电脑	dian nao
是否	shi fou
联系	lian xi
意思	yi si
游戏	you xi
老师	lao shi
特别	te bie
个人	ge ren
只要	zhi yao
文件	wen jian
能够	neng gou
有点	you dian
软件	ruan jian
几个	ji ge
过去	guo qu
学习	xue xi
社会	she hui
过来	guo lai
给你	gei ni
男人	nan ren
了解	liao jie
只能	zhi neng
世界	shi jie
吃饭	chi fan
不好	bu hao
不用	bu yong
的话	de hua
表示	biao shi
嘿嘿	hei hei
发生	fa sheng
得到	de dao
基本	ji ben
处理	chu li
同学	tong xue
老婆	lao po
照片	zhao pian
客户	ke hu
方法	fang fa
完成	wan cheng
关于	guan yu
有些	you xie
当时	dang shi
刚才	gang cai
实现	shi xian
中的	zhong de
原来	yuan lai
包括	bao kuo
解决	jie jue
一种	yi zhong
反正	fan zheng
政府	zheng fu
根据	gen ju
重要	zhong yao
成功	cheng gong
下载	xia zai
考虑	kao lv
能力	neng li
过程	guo cheng
他的	ta de
分析	fen xi
机会	ji hui
下午	xia wu
提高	ti gao
认识	ren shi
注意	zhu yi
介绍	jie shao
进入	jin ru
之前	zhi qian
日本	ri ben
存在	cun zai
其中	qi zhong
今年	jin nian
增加	zeng jia
记者	ji zhe
无法	wu fa
出去	chu qu
国内	guo nei
决定	jue ding
相关	xiang guan
人家	ren jia
完全	wan quan
组织	zu zhi
单位	dan wei
有人	you ren
业务	ye wu
测试	ce shi
还要	hai yao
任何	ren he
正在	zheng zai
后来	hou lai
专业	zhuan ye
计划	ji hua
之间	zhi jian
每天	mei tian
除了	chu le
建议	jian yi
论坛	lun tan
投资	tou zi
具有	ju you
空间	kong jian
不行	bu xing
原因	yuan yin
开发	kai fa
建立	jian li
名字	ming zi
参加	can jia
回家	hui jia
人员	ren yuan
全部	quan bu
建设	jian she
显示	xian shi
睡觉	shui jiao
回去	hui qu
甚至	shen zhi
找到	zhao dao
最好	zui hao
我国	wo guo
获得	huo de
到了	dao le
部门	bu men
这次	zhe ci
人们	ren men
标准	biao zhun
经济	jing ji
控制	kong zhi
网上	wang shang
程序	cheng xu
简单	jian dan
让我	rang wo
一切	yi qie
效果	xiao guo
本来	ben lai
上班	shang ban
城市	cheng shi
真是	zhen shi
哪个	na ge
电影	dian ying
也许	ye xu
达到	da dao
好了	hao le
速度	su du
具体	ju ti
负责	fu ze
环境	huan jing
小时	xiao shi
银行	yin hang
经常	jing chang
办法	ban fa
消息	xiao xi
生产	sheng chan
大学	da xue
申请	shen qing
提出	ti chu
说话	shuo hua
因此	yin ci
看来	kan lai
我是	wo shi
来说	lai shuo
相信	xiang xin
许多	xu duo
说明	shuo ming
作用	zuo yong
安全	an quan
你好	ni hao
各种	ge zhong
终于	zhong yu
真正	zhen zheng
全国	quan guo
记得	ji de
正常	zheng chang
资料	zi liao
调整	tiao zheng
领导	ling dao
操作	cao zuo
采用	cai yong
下来	xia lai
国际	guo ji
努力	nu li
行业	hang ye
图片	tu pian
没事	mei shi
以上	yi shang
有关	you guan
另外	ling wai
修改	xiu gai
接受	jie shou
容易	rong yi
才能	cai neng
有没有	you mei you
设置	she zhi
妈妈	ma ma
以为	yi wei
产生	chan sheng
明白	ming bai
历史	li shi
上面	shang mian
合作	he zuo
目标	mu biao
代表	dai biao
我也	wo ye
总是	zong shi
需求	xu qiu
第一	di yi
这一	zhe yi
安装	an zhuang
广告	guang gao
那样	na yang
按照	an zhao
股票	gu piao
也不	ye bu
也有	ye you
文化	wen hua
不断	bu duan
确定	que ding
销售	xiao shou
服务器	fu wu qi
好好	hao hao
中心	zhong xin
左右	zuo you
应用	ying yong
麻烦	ma fan
经验	jing yan
"""

    static let sentences = """
这个周末天气很好	zhe ge zhou mo tian qi hen hao
然后开车去郊外的公园	ran hou kai che qu jiao wai de gong yuan
公园里人不多	gong yuan li ren bu duo
草地上开满了小花	cao di shang kai man le xiao hua
孩子们在湖边喂鸭子	hai zi men zai hu bian wei ya zi
玩得特别开心	wan de te bie kai xin
中午我们在树下野餐	zhong wu wo men zai shu xia ye can
吃了自己做的三明治	chi le zi ji zuo de san ming zhi
下午起风了	xia wu qi feng le
我们放了一会儿风筝	wo men fang le yi hui er feng zheng
四点多才回家	si dian duo cai hui jia
虽然有点累	sui ran you dian lei
本周项目整体进展顺利	ben zhou xiang mu zheng ti jin zhan shun li
后端接口基本联调通过	hou duan jie kou ji ben lian diao tong guo
影响了测试进度	ying xiang le ce shi jin du
下周计划先解决环境问题	xia zhou ji hua xian jie jue huan jing wen ti
再安排两天时间做性能优化	zai an pai liang tian shi jian zuo xing neng you hua
并和产品经理确认最终方案	bing he chan pin jing li que ren zui zhong fang an
如果没有其他风险	ru guo mei you qi ta feng xian
预计月底可以按时上线	yu ji yue di ke yi an shi shang xian
小时候家里书不多	xiao shi hou jia li shu bu duo
我最喜欢去学校的图书馆	wo zui xi huan qu xue xiao de tu shu guan
那里有一排排高高的书架	na li you yi pai pai gao gao de shu jia
阳光从窗户照进来	yang guang cong chuang hu zhao jin lai
空气里有一种旧纸张的味道	kong qi li you yi zhong jiu zhi zhang de wei dao
每次借到一本新书	mei ci jie dao yi ben xin shu
后来工作越来越忙	hou lai gong zuo yue lai yue mang
读书的时间越来越少	du shu de shi jian yue lai yue shao
手机占据了大部分的空闲	shou ji zhan ju le da bu fen de kong xian
每天哪怕只读二十分钟	mei tian na pa zhi du er shi fen zhong
也觉得心里安静了很多	ye jue de xin li an jing le hen duo
会有自动修正功能么	hui you zi dong xiu zheng gong neng me
比如根据输入的内容	bi ru gen ju shu ru de nei rong
我明明打错了	wo ming ming da cuo le
还是只是我单纯输入的问题	hai shi zhi shi wo dan chun shu ru de wen ti
这个倒是没有实际的例子	zhe ge dao shi mei you shi ji de li zi
从而有经常修正的情况	cong er you jing chang xiu zheng de qing kuang
总感觉哪里不一样	zong gan jue na li bu yi yang
是在候选上的问题么	shi zai hou xuan shang de wen ti me
这个感觉有点大	zhe ge gan jue you dian da
不少界面都要改	bu shao jie mian dou yao gai
整理方案吧	zheng li fang an ba
这个感觉还是挺重要的	zhe ge gan jue hai shi ting zhong yao de
和大厂的这些做法	he da chang de zhe xie zuo fa
晚上一起吃饭吗	wan shang yi qi chi fan ma
我刚到公司	wo gang dao gong si
等会儿给你打电话	deng hui er gei ni da dian hua
明天下午三点开会	ming tian xia wu san dian kai hui
记得带电脑	ji de dai dian nao
这个周末有什么安排	zhe ge zhou mo you shen me an pai
我马上发给你	wo ma shang fa gei ni
你到哪了	ni dao na le
我在门口等你	wo zai men kou deng ni
今天太累了	jin tian tai lei le
早点休息吧	zao dian xiu xi ba
孩子今天发烧了	hai zi jin tian fa shao le
我请个假	wo qing ge jia
周五之前把报告交上来	zhou wu zhi qian ba bao gao jiao shang lai
谢谢你的帮助	xie xie ni de bang zhu
改天请你喝咖啡	gai tian qing ni he ka fei
快递到了吗	kuai di dao le ma
我放在前台了	wo fang zai qian tai le
这家店的菜味道不错	zhe jia dian de cai wei dao bu cuo
下次再来	xia ci zai lai
路上堵车	lu shang du che
可能要晚十分钟	ke neng yao wan shi fen zhong
你看到我发的消息了吗	ni kan dao wo fa de xiao xi le ma
我们下周去上海出差	wo men xia zhou qu shang hai chu chai
这个价格有点贵	zhe ge jia ge you dian gui
能便宜一点吗	neng pian yi yi dian ma
最近天气变冷了	zui jin tian qi bian leng le
多穿点衣服	duo chuan dian yi fu
我已经把钱转给你了	wo yi jing ba qian zhuan gei ni le
你查收一下	ni cha shou yi xia
生日快乐	sheng ri kuai le
祝你天天开心	zhu ni tian tian kai xin
周末带孩子去公园玩	zhou mo dai hai zi qu gong yuan wan
今天的会议推迟到明天	jin tian de hui yi tui chi dao ming tian
我在地铁上	wo zai di tie shang
信号不太好	xin hao bu tai hao
老师说明天要交作业	lao shi shuo ming tian yao jiao zuo ye
我想换一个新手机	wo xiang huan yi ge xin shou ji
这本书写得很好	zhe ben shu xie de hen hao
推荐你看看	tui jian ni kan kan
下班以后去健身房	xia ban yi hou qu jian shen fang
他说的话你别放在心上	ta shuo de hua ni bie fang zai xin shang
"""
}
