#!/bin/sh

# Name:        gfwlist2dnsmasq.sh
# Desription:  A shell script which convert gfwlist into dnsmasq rules.
# Version:     0.9.0 (2020.04.09)
# Author:      Cokebar Chi
# Website:     https://github.com/cokebar

# 颜色输出函数 - 用于终端彩色输出
green() {
    printf '\033[1;31;32m'
    printf -- "%b" "$1"
    printf '\033[0m'
}

# 红色输出函数
red() {
    printf '\033[1;31;31m'
    printf -- "%b" "$1"
    printf '\033[0m'
}

# 黄色输出函数
yellow() {
    printf '\033[1;31;33m'
    printf -- "%b" "$1"
    printf '\033[0m'
}

# 使用说明函数
usage() {
    cat <<-EOF

Usage: sh gfwlist2dnsmasq.sh [options] -o FILE
Valid options are:
    -d, --dns <dns_ip>
                DNS IP address for the GfwList Domains (Default: 127.0.0.1)
    -p, --port <dns_port>
                DNS Port for the GfwList Domains (Default: 5353)
    -n, --nftset <nftset_name>
                Nftset name for the GfwList domains
                (If not given, nftset rules will not be generated.)
    -o, --output <FILE>
                /path/to/output_filename
    -i, --insecure
                Force bypass certificate validation (insecure)
    -l, --domain-list
                Convert Gfwlist into domain list instead of dnsmasq rules
                (If this option is set, DNS IP/Port & nftset are not needed)
        --exclude-domain-file <FILE>
                Delete specific domains in the result from a domain list text file
                Please put one domain per line
        --extra-domain-file <FILE>
                Include extra domains to the result from a domain list text file
                This file will be processed after the exclude-domain-file
                Please put one domain per line
    -h, --help
                Usage
EOF
    exit $1
}

# 清理临时文件和退出函数
clean_and_exit(){
    # Clean up temp files
    printf 'Cleaning up... '
    rm -rf $TMP_DIR
    green 'Done\n\n'
    [ $1 -eq 0 ] && green 'Job Finished.\n\n' || red 'Exit with Error code '$1'.\n'
    exit $1
}

# 检查依赖工具函数
check_depends(){
    which sed base64 mktemp >/dev/null 2>&1
    if [ $? != 0 ]; then
        red 'Error: Missing Dependency.\nPlease check whether you have the following binaries on you system:\nwhich, sed, base64, mktemp.\n'
        exit 3
    fi
    which curl >/dev/null 2>&1
    if [ $? != 0 ]; then
        which wget >/dev/null 2>&1
        if [ $? != 0 ]; then
            red 'Error: Missing Dependency.\nEither curl or wget required.\n'
            exit 3
        fi
        USE_WGET=1
    else
        USE_WGET=0
    fi

    # 根据系统类型设置不同的base64解码命令
    SYS_KERNEL=`uname -s`
    if [ $SYS_KERNEL = "Darwin"  -o $SYS_KERNEL = "FreeBSD" ]; then
        BASE64_DECODE='base64 -D -i'
        SED_ERES='sed -E'
    else
        BASE64_DECODE='base64 -d'
        SED_ERES='sed -r'
    fi
}

# 参数处理函数
get_args(){
    # 默认参数设置
    OUT_TYPE='DNSMASQ_RULES'  # 输出类型：DNSMASQ规则或域名列表
    DNS_IP='127.0.0.1'       # 默认DNS服务器IP
    DNS_PORT='5353'          # 默认DNS端口
    NFTSET_NAME=''           # nftset名称
    FILE_FULLPATH=''         # 输出文件完整路径
    CURL_EXTARG=''           # curl额外参数
    WGET_EXTARG=''           # wget额外参数
    WITH_NFTSET=0            # 是否包含nftset规则
    EXTRA_DOMAIN_FILE=''     # 额外域名文件
    EXCLUDE_DOMAIN_FILE=''   # 排除域名文件
    
    # IPv4和IPv6地址的正则表达式模式
    IPV4_PATTERN='^((2[0-4][0-9]|25[0-5]|[01]?[0-9][0-9]?)\.){3}(2[0-4][0-9]|25[0-5]|[01]?[0-9][0-9]?)$'
    IPV6_PATTERN='^((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:)))(%.+)?$'

    # 解析命令行参数
    while [ ${#} -gt 0 ]; do
        case "${1}" in
            --help | -h)
                usage 0
                ;;
            --domain-list | -l)
                OUT_TYPE='DOMAIN_LIST'  # 设置为域名列表输出模式
                ;;
            --insecure | -i)
                CURL_EXTARG='--insecure'          # curl跳过证书验证
                WGET_EXTARG='--no-check-certificate'  # wget跳过证书验证
                ;;
            --dns | -d)
                DNS_IP="$2"          # 设置DNS服务器IP
                shift
                ;;
            --port | -p)
                DNS_PORT="$2"        # 设置DNS服务器端口
                shift
                ;;
            --nftset | -n)
                NFTSET_NAME="$2"      # 设置nftset名称
                shift
                ;;
            --output | -o)
                OUT_FILE="$2"        # 设置输出文件路径
                shift
                ;;
            --extra-domain-file)
                EXTRA_DOMAIN_FILE="$2"  # 设置额外域名文件
                shift
                ;;
           --exclude-domain-file)
                EXCLUDE_DOMAIN_FILE="$2"  # 设置排除域名文件
                shift
                ;;
            *)
                red "Invalid argument: $1"
                usage 1
                ;;
        esac
        shift 1
    done

    # 检查输出文件路径是否有效
    if [ -z $OUT_FILE ]; then
        red 'Error: Please specify the path to the output file(using -o/--output argument).\n'
        exit 1
    else
        if [ -z ${OUT_FILE##*/} ]; then
            red 'Error: '$OUT_FILE' is a path, not a file.\n'
            exit 1
        else
            if [ ${OUT_FILE}a != ${OUT_FILE%/*}a ] && [ ! -d ${OUT_FILE%/*} ]; then
                red 'Error: Folder do not exist: '${OUT_FILE%/*}'\n'
                exit 1
            fi
        fi
    fi

    # 当输出类型为DNSMASQ规则时，验证DNS设置和nftset名称
    if [ $OUT_TYPE = 'DNSMASQ_RULES' ]; then
        # 检查DNS IP是否有效
        IPV4_TEST=$(echo $DNS_IP | grep -E $IPV4_PATTERN)
        IPV6_TEST=$(echo $DNS_IP | grep -E $IPV6_PATTERN)
        if [ "$IPV4_TEST" != "$DNS_IP" -a "$IPV6_TEST" != "$DNS_IP" ]; then
            red 'Error: Please enter a valid DNS server IP address.\n'
            exit 1
        fi

        # 检查DNS端口是否有效
        if [ $DNS_PORT -lt 1 -o $DNS_PORT -gt 65535 ]; then
            red 'Error: Please enter a valid DNS server port.\n'
            exit 1
        fi
        
        # 检查nftset名称是否有效
        if [ -z $NFTSET_NAME ]; then
            WITH_NFTSET=0
        else
            NFTSET_TEST=$(echo $NFTSET_NAME | grep -E '^\w+(#\w+)*$')
            echo $NFTSET_TEST
            if [ "$NFTSET_TEST" != "$NFTSET_NAME" ]; then
                red 'Error: Please enter a valid I set name.\n'
                exit 1
            else
                WITH_NFTSET=1
            fi
        fi
    fi

    # 检查额外域名文件是否存在
    if [ ! -z $EXTRA_DOMAIN_FILE ] && [ ! -f $EXTRA_DOMAIN_FILE ]; then
        yellow 'WARNING:\nExtra domain file does not exist, ignored.\n\n'
        EXTRA_DOMAIN_FILE=''
    fi

    # 检查排除域名文件是否存在
    if [ ! -z $EXCLUDE_DOMAIN_FILE ] && [ ! -f $EXCLUDE_DOMAIN_FILE ]; then
        yellow 'WARNING:\nExclude domain file does not exist, ignored.\n\n'
        EXCLUDE_DOMAIN_FILE=''
    fi
}

# 主要处理函数
process(){
    # 设置全局变量
    if [ -z $GFWLIST_URL ]; then
      GFWLIST_URL='https://github.com/gfwlist/gfwlist/raw/master/gfwlist.txt'  # GFWList源URL
    fi
    TMP_DIR=`mktemp -d /tmp/gfwlist2dnsmasq.XXXXXX`  # 创建临时目录
    BASE64_FILE="$TMP_DIR/base64.txt"                # 存储下载的base64编码文件
    GFWLIST_FILE="$TMP_DIR/gfwlist.txt"              # 存储解码后的GFWList
    DOMAIN_TEMP_FILE="$TMP_DIR/gfwlist2domain.tmp"    # 临时域名文件
    DOMAIN_FILE="$TMP_DIR/gfwlist2domain.txt"        # 最终域名列表文件
    CONF_TMP_FILE="$TMP_DIR/gfwlist.conf.tmp"         # 临时配置文件
    OUT_TMP_FILE="$TMP_DIR/gfwlist.out.tmp"           # 临时输出文件

    # 下载GFWList并解码为明文
    printf "Fetching GFWList from $GFWLIST_URL ... \n"
    printf "You can overwrite gfwlist url via 'export GFWLIST_URL=https://example.com/gfwlist.txt' \n"
    if [ $USE_WGET = 0 ]; then
        curl -s -L $CURL_EXTARG -o$BASE64_FILE $GFWLIST_URL
    else
        wget -q $WGET_EXTARG -O$BASE64_FILE $GFWLIST_URL
    fi
    if [ $? != 0 ]; then
        red '\nFailed to fetch gfwlist.txt. Please check your Internet connection, and check TLS support for curl/wget.\n'
        clean_and_exit 2
    fi
    $BASE64_DECODE $BASE64_FILE > $GFWLIST_FILE || ( red 'Failed to decode gfwlist.txt. Quit.\n'; clean_and_exit 2 )
    green 'Done.\n\n'

    # 定义正则表达式模式用于过滤和处理域名
    IGNORE_PATTERN='^\!|\[|^@@|(https?://){0,1}[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'  # 忽略的行模式
    HEAD_FILTER_PATTERN='s#^(\|\|?)?(https?://)?##g'  # 过滤行首的模式
    TAIL_FILTER_PATTERN='s#/.*$|%2F.*$##g'  # 过滤行尾的模式
    DOMAIN_PATTERN='([a-zA-Z0-9][-a-zA-Z0-9]*(\.[a-zA-Z0-9][-a-zA-Z0-9]*)+)'  # 域名匹配模式
    HANDLE_WILDCARD_PATTERN='s#^(([a-zA-Z0-9]*\*[-a-zA-Z0-9]*)?(\.))?([a-zA-Z0-9][-a-zA-Z0-9]*(\.[a-zA-Z0-9][-a-zA-Z0-9]*)+)(\*[a-zA-Z0-9]*)?#\4#g'  # 处理通配符的模式

    # 转换GFWList为指定输出类型
    printf 'Converting GfwList to ' && green $OUT_TYPE && printf ' ...\n' 
    yellow '\nWARNING:\nThe following lines in GfwList contain regex, and might be ignored:\n\n'
    cat $GFWLIST_FILE | grep -n '^/.*$'
    yellow "\nThis script will try to convert some of the regex rules. But you should know this may not be a equivalent conversion.\nIf there's regex rules which this script do not deal with, you should add the domain manually to the list.\n\n"
    # 应用过滤规则处理GFWList
    grep -vE $IGNORE_PATTERN $GFWLIST_FILE | $SED_ERES $HEAD_FILTER_PATTERN | $SED_ERES $TAIL_FILTER_PATTERN | grep -E $DOMAIN_PATTERN | $SED_ERES $HANDLE_WILDCARD_PATTERN > $DOMAIN_TEMP_FILE

    # 添加Google搜索域名
    printf 'google.com\ngoogle.ad\ngoogle.ae\ngoogle.com.af\ngoogle.com.ag\ngoogle.com.ai\ngoogle.al\ngoogle.am\ngoogle.co.ao\ngoogle.com.ar\ngoogle.as\ngoogle.at\ngoogle.com.au\ngoogle.az\ngoogle.ba\ngoogle.com.bd\ngoogle.be\ngoogle.bf\ngoogle.bg\ngoogle.com.bh\ngoogle.bi\ngoogle.bj\ngoogle.com.bn\ngoogle.com.bo\ngoogle.com.br\ngoogle.bs\ngoogle.bt\ngoogle.co.bw\ngoogle.by\ngoogle.com.bz\ngoogle.ca\ngoogle.cd\ngoogle.cf\ngoogle.cg\ngoogle.ch\ngoogle.ci\ngoogle.co.ck\ngoogle.cl\ngoogle.cm\ngoogle.cn\ngoogle.com.co\ngoogle.co.cr\ngoogle.com.cu\ngoogle.cv\ngoogle.com.cy\ngoogle.cz\ngoogle.de\ngoogle.dj\ngoogle.dk\ngoogle.dm\ngoogle.com.do\ngoogle.dz\ngoogle.com.ec\ngoogle.ee\ngoogle.com.eg\ngoogle.es\ngoogle.com.et\ngoogle.fi\ngoogle.com.fj\ngoogle.fm\ngoogle.fr\ngoogle.ga\ngoogle.ge\ngoogle.gg\ngoogle.com.gh\ngoogle.com.gi\ngoogle.gl\ngoogle.gm\ngoogle.gp\ngoogle.gr\ngoogle.com.gt\ngoogle.gy\ngoogle.com.hk\ngoogle.hn\ngoogle.hr\ngoogle.ht\ngoogle.hu\ngoogle.co.id\ngoogle.ie\ngoogle.co.il\ngoogle.im\ngoogle.co.in\ngoogle.iq\ngoogle.is\ngoogle.it\ngoogle.je\ngoogle.com.jm\ngoogle.jo\ngoogle.co.jp\ngoogle.co.ke\ngoogle.com.kh\ngoogle.ki\ngoogle.kg\ngoogle.co.kr\ngoogle.com.kw\ngoogle.kz\ngoogle.la\ngoogle.com.lb\ngoogle.li\ngoogle.lk\ngoogle.co.ls\ngoogle.lt\ngoogle.lu\ngoogle.lv\ngoogle.com.ly\ngoogle.co.ma\ngoogle.md\ngoogle.me\ngoogle.mg\ngoogle.mk\ngoogle.ml\ngoogle.com.mm\ngoogle.mn\ngoogle.ms\ngoogle.com.mt\ngoogle.mu\ngoogle.mv\ngoogle.mw\ngoogle.com.mx\ngoogle.com.my\ngoogle.co.mz\ngoogle.com.na\ngoogle.com.nf\ngoogle.com.ng\ngoogle.com.ni\ngoogle.ne\ngoogle.nl\ngoogle.no\ngoogle.com.np\ngoogle.nr\ngoogle.nu\ngoogle.co.nz\ngoogle.com.om\ngoogle.com.pa\ngoogle.com.pe\ngoogle.com.pg\ngoogle.com.ph\ngoogle.com.pk\ngoogle.pl\ngoogle.pn\ngoogle.com.pr\ngoogle.ps\ngoogle.pt\ngoogle.com.py\ngoogle.com.qa\ngoogle.ro\ngoogle.ru\ngoogle.rw\ngoogle.com.sa\ngoogle.com.sb\ngoogle.sc\ngoogle.se\ngoogle.com.sg\ngoogle.sh\ngoogle.si\ngoogle.sk\ngoogle.com.sl\ngoogle.sn\ngoogle.so\ngoogle.sm\ngoogle.sr\ngoogle.st\ngoogle.com.sv\ngoogle.td\ngoogle.tg\ngoogle.co.th\ngoogle.com.tj\ngoogle.tk\ngoogle.tl\ngoogle.tm\ngoogle.tn\ngoogle.to\ngoogle.com.tr\ngoogle.tt\ngoogle.com.tw\ngoogle.co.tz\ngoogle.com.ua\ngoogle.co.ug\ngoogle.co.uk\ngoogle.com.uy\ngoogle.co.uz\ngoogle.com.vc\ngoogle.co.ve\ngoogle.vg\ngoogle.co.vi\ngoogle.com.vn\ngoogle.vu\ngoogle.ws\ngoogle.rs\ngoogle.co.za\ngoogle.co.zm\ngoogle.co.zw\ngoogle.cat\n' >> $DOMAIN_TEMP_FILE
    printf 'Google search domains... ' && green 'Added\n'

    # 添加blogspot域名
    printf 'blogspot.ca\nblogspot.co.uk\nblogspot.com\nblogspot.com.ar\nblogspot.com.au\nblogspot.com.br\nblogspot.com.by\nblogspot.com.co\nblogspot.com.cy\nblogspot.com.ee\nblogspot.com.eg\nblogspot.com.es\nblogspot.com.mt\nblogspot.com.ng\nblogspot.com.tr\nblogspot.com.uy\nblogspot.de\nblogspot.gr\nblogspot.in\nblogspot.mx\nblogspot.ch\nblogspot.fr\nblogspot.ie\nblogspot.it\nblogspot.pt\nblogspot.ro\nblogspot.sg\nblogspot.be\nblogspot.no\nblogspot.se\nblogspot.jp\nblogspot.in\nblogspot.ae\nblogspot.al\nblogspot.am\nblogspot.ba\nblogspot.bg\nblogspot.ch\nblogspot.cl\nblogspot.cz\nblogspot.dk\nblogspot.fi\nblogspot.gr\nblogspot.hk\nblogspot.hr\nblogspot.hu\nblogspot.ie\nblogspot.is\nblogspot.kr\nblogspot.li\nblogspot.lt\nblogspot.lu\nblogspot.md\nblogspot.mk\nblogspot.my\nblogspot.nl\nblogspot.no\nblogspot.pe\nblogspot.qa\nblogspot.ro\nblogspot.ru\nblogspot.se\nblogspot.sg\nblogspot.si\nblogspot.sk\nblogspot.sn\nblogspot.tw\nblogspot.ug\nblogspot.cat\n' >> $DOMAIN_TEMP_FILE
    printf 'Blogspot domains... ' && green 'Added\n'

    # 添加twimg.edgesuite.net
    printf 'twimg.edgesuite.net\n' >> $DOMAIN_TEMP_FILE
    printf 'twimg.edgesuite.net... ' && green 'Added\n'

    # 应用排除域名文件
    if [ ! -z $EXCLUDE_DOMAIN_FILE ]; then
        for line in $(cat $EXCLUDE_DOMAIN_FILE)
        do
            cat $DOMAIN_TEMP_FILE | grep -vF -f $EXCLUDE_DOMAIN_FILE > $DOMAIN_FILE
        done
        printf 'Domains in exclude domain file '$EXCLUDE_DOMAIN_FILE'... ' && green 'Deleted\n'
    else
        cat $DOMAIN_TEMP_FILE > $DOMAIN_FILE
    fi

    # 添加额外域名
    if [ ! -z $EXTRA_DOMAIN_FILE ]; then
        cat $EXTRA_DOMAIN_FILE >> $DOMAIN_FILE
        printf 'Extra domain file '$EXTRA_DOMAIN_FILE'... ' && green 'Added\n'
    fi

    # 根据输出类型进行相应处理
    if [ $OUT_TYPE = 'DNSMASQ_RULES' ]; then
        # 生成dnsmasq规则
        # 将域名分为包含youtube/googlevideo和不包含youtube/googlevideo两类
        grep -Ei 'youtube|googlevideo' $DOMAIN_FILE > $TMP_DIR/youtube_googlevideo_domains.txt
        grep -Eiv 'youtube|googlevideo' $DOMAIN_FILE > $TMP_DIR/non_youtube_googlevideo_domains.txt
        
        # 创建空的配置文件
        > $CONF_TMP_FILE
        
        if [ $WITH_NFTSET -eq 1 ]; then
            green 'Nftset rules included.'
            
            # 处理非youtube/googlevideo域名
            if [ -s $TMP_DIR/non_youtube_googlevideo_domains.txt ]; then
                sort -u $TMP_DIR/non_youtube_googlevideo_domains.txt | $SED_ERES 's@(.+)@server=/\1/'$DNS_IP'\#'$DNS_PORT'\
nftset=/\1/'$NFTSET_NAME'@g' >> $CONF_TMP_FILE
            fi
            
            # 处理youtube/googlevideo域名
            if [ -s $TMP_DIR/youtube_googlevideo_domains.txt ]; then
                sort -u $TMP_DIR/youtube_googlevideo_domains.txt | $SED_ERES 's@(.+)@server=/\1/'$DNS_IP'\#'$DNS_PORT'\
nftset=/\1/'$NFTSET_NAME'_youtube@g' >> $CONF_TMP_FILE
            fi
        else
            green 'Nftset rules not included.'
            sort -u $DOMAIN_FILE | $SED_ERES 's#(.+)#server=/\1/'$DNS_IP'\#'$DNS_PORT'#g' > $CONF_TMP_FILE
        fi

        # 生成最终输出文件
        echo '# dnsmasq rules generated by gfwlist' > $OUT_TMP_FILE
        echo "# Last Updated on $(date "+%Y-%m-%d %H:%M:%S")" >> $OUT_TMP_FILE
        echo '# ' >> $OUT_TMP_FILE
        cat $CONF_TMP_FILE >> $OUT_TMP_FILE
        cp $OUT_TMP_FILE $OUT_FILE
    else
        # 生成纯域名列表
        sort -u $DOMAIN_FILE > $OUT_TMP_FILE
    fi

    cp $OUT_TMP_FILE $OUT_FILE
    printf '\nConverting GfwList to '$OUT_TYPE'... ' && green 'Done\n\n'

    # 清理临时文件并退出
    clean_and_exit 0
}

# 主函数
main() {
    if [ -z "$1" ]; then
        usage 0  # 无参数时显示使用说明
    else
        check_depends    # 检查依赖
        get_args "$@"    # 处理参数
        green '\nJob Started.\n\n'
        process          # 执行主要处理流程
    fi
}

# 脚本入口点
main "$@"