#!/bin/bash
#
# check.sh —— 查看测试库里关怀系统的真实状态
#
# 用途：跑完 App 之后，看数据库里到底存了什么。
#      print 打印的是「代码以为自己干了什么」，这里看到的才是「实际存进去了什么」。
#
# 用法：
#   1. Xcode 的 Scheme 里勾上 -UseTestStore（Edit Scheme → Run → Arguments）
#   2. 跑一次 App，然后退出
#   3. 终端里 cd 到项目目录，敲：bash check.sh
#
# 注意：查之前先把 App 关掉，否则可能有没落盘的改动。

set -e

DEVICE="${1:-iPhone 17 Pro}"          # 可以传参换机型：bash check.sh "iPhone 17"
BUNDLE="com.shiying.Slime"

# 系统 xcode-select 指向 Command Line Tools，simctl 得靠这个环境变量找到完整 Xcode
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# 模拟器的 App 数据目录是一串 UUID，只能问系统要
DIR=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data 2>/dev/null) || {
    echo "❌ 找不到 App 数据目录。检查：模拟器开着吗？App 装了吗？机型名对吗？"
    echo "   查机型：xcrun simctl list devices available"
    exit 1
}

DB="$DIR/Library/Application Support/Slime-Test.sqlite"

if [ ! -f "$DB" ]; then
    echo "❌ 测试库不存在：$DB"
    echo "   多半是没勾 -UseTestStore 就跑了 App（那样用的是正式库 Slime.sqlite）。"
    exit 1
fi

# Core Data 的 Date 存的是「距 2001-01-01 的秒数」，Unix 时间戳从 1970 算，差 978307200 秒。
# 不加 'localtime' 出来的是 UTC，东八区会整体差一天。
EPOCH=978307200

q() { sqlite3 -header -column "$DB" "$1"; }

echo "📂 $DB"
echo
echo "════════ 蛋（这就是发给 AI 的窗口内容）════════"
q "select date(zdate+$EPOCH,'unixepoch','localtime') as 日期,
          zemotion as 情绪,
          datetime(zcreatedat+$EPOCH,'unixepoch','localtime') as 孵出时刻,
          ztext as 总结
   from ZDAYEGG order by zdate;"

echo
echo "════════ 关怀 ════════"
q "select zstatus as 状态,
          datetime(zcreatedat+$EPOCH,'unixepoch','localtime') as 生成于,
          ifnull(datetime(zretiredat+$EPOCH,'unixepoch','localtime'),'—— 还挂着') as 退场于,
          zreferenceddates as 引用日期,
          ztext as 文案
   from ZCAREMESSAGE order by zcreatedat desc;"

echo
echo "════════ 检查日志（最近 5 次）════════"
q "select datetime(zcheckedat+$EPOCH,'unixepoch','localtime') as 检查于,
          case zgatepassed when 1 then '过' else '挡' end as 闸门,
          ifnull(zgatereason,'') as 挡在哪条,
          case zaicalled when 1 then '是' else '否' end as 调AI,
          zlatencyms as 耗时ms,
          case zfinalshown when 1 then '是' else '否' end as 展示,
          ifnull(zdropreason,'') as 丢弃原因
   from ZCARECHECK order by zcheckedat desc limit 5;"

echo
echo "════════ 日记条数 ════════"
q "select count(*) as 篇数 from ZPOST;"
