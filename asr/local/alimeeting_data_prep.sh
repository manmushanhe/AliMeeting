#!/usr/bin/env bash
# Set bash to 'debug' mode, it will exit on :
# -e 'error', -u 'undefined variable', -o ... 'error in pipeline', -x 'print commands',
set -e
set -u
set -o pipefail

log() {
    local fname=${BASH_SOURCE[1]##*/}
    echo -e "$(date '+%Y-%m-%dT%H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}

help_messge=$(cat << EOF
Usage: $0

Options:
    --no_overlap (bool): Whether to ignore the overlapping utterance in the training set.
    --tgt (string): Which set to process, test or train.
EOF
)

SECONDS=0
tgt=Train #Train or Eval


log "$0 $*"
echo $tgt
. ./utils/parse_options.sh

. ./db.sh
. ./path.sh
. ./cmd.sh

if [ $# -gt 2 ]; then
    log "${help_message}"
    exit 2
fi

AliMeeting="/Work21/2021/luhaoyu/A-data/Alimeeting/"

if [ -z "${AliMeeting}" ]; then
  log "Error: \$AliMeeting is not set in db.sh."
  exit 2
fi

if [ ! -d "${AliMeeting}" ]; then
  log "Error: ${AliMeeting} is empty."
  exit 2
fi

# To absolute path 获得绝对路径
AliMeeting=$(cd ${AliMeeting}; pwd)
echo $AliMeeting
#原始数据目录
far_raw_dir=${AliMeeting}/${tgt}_Ali_far/
near_raw_dir=${AliMeeting}/${tgt}_Ali_near/

#处理后数据目录
far_dir=data/local/${tgt}_Ali_far
near_dir=data/local/${tgt}_Ali_near
stage=3
stop_stage=3
mkdir -p $far_dir
mkdir -p $near_dir

if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then 
    log "stage 1:process alimeeting near dir"
    #搜索音频，结果写入wavlist文件
    find -L $near_raw_dir/audio_dir -iname "*.wav" >  $near_dir/wavlist
    awk -F '/' '{print $NF}' $near_dir/wavlist | awk -F '.' '{print $1}' > $near_dir/uttid  
    #分析find获取得内容得到uttid文件，uttid即是音频文件文件名 
    find -L $near_raw_dir/textgrid_dir  -iname "*.TextGrid" > $near_dir/textgrid.flist
    #
    n1_wav=$(wc -l < $near_dir/wavlist)
    #音频数
    n2_text=$(wc -l < $near_dir/textgrid.flist)
    #文本数
    log  near file found $n1_wav wav and $n2_text text.

    paste $near_dir/uttid $near_dir/wavlist > $near_dir/wav_raw.scp
    #获取wav_rawscp文件，每一行是wavid和对应的路径

    cat $near_dir/wav_raw.scp | awk '{printf("%s sox -t wav  %s -r 16000 -b 16 -c 1 -t wav  - |\n", $1, $2)}'  > $near_dir/wav.scp
    #获取wav.scp
    
    python local/alimeeting_process_textgrid.py --path $near_dir --no-overlap False
    
    cat $near_dir/text_all | local/text_normalize.pl | local/text_format.pl | sort -u > $near_dir/text
    
    utils/filter_scp.pl -f 1 $near_dir/text $near_dir/utt2spk_all | sort -u > $near_dir/utt2spk
    #sed -e 's/ [a-z,A-Z,_,0-9,-]\+SPK/ SPK/'  $near_dir/utt2spk_old >$near_dir/tmp1
    #sed -e 's/-[a-z,A-Z,0-9]\+$//' $near_dir/tmp1 | sort -u > $near_dir/utt2spk
    utils/utt2spk_to_spk2utt.pl $near_dir/utt2spk > $near_dir/spk2utt
    utils/filter_scp.pl -f 1 $near_dir/text $near_dir/segments_all | sort -u > $near_dir/segments
    sed -e 's/ $//g' $near_dir/text> $near_dir/tmp1
    sed -e 's/！//g' $near_dir/tmp1> $near_dir/tmp2
    sed -e 's/(\~)//g' $near_dir/tmp2> $near_dir/tmp3
    sed -e 's/(SIL)//g' $near_dir/tmp3> $near_dir/tmp4
    sed -e 's/(\/OVERLAP)//g' $near_dir/tmp4> $near_dir/text

fi


if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
    log "stage 2:process alimeeting far dir"
    
    find -L $far_raw_dir/audio_dir -iname "*.wav" >  $far_dir/wavlist
    awk -F '/' '{print $NF}' $far_dir/wavlist | awk -F '.' '{print $1}' > $far_dir/uttid   
    find -L $far_raw_dir/textgrid_dir  -iname "*.TextGrid" > $far_dir/textgrid.flist
    n1_wav=$(wc -l < $far_dir/wavlist)
    n2_text=$(wc -l < $far_dir/textgrid.flist)
    log  far file found $n1_wav wav and $n2_text text.

    paste $far_dir/uttid $far_dir/wavlist > $far_dir/wav_raw.scp

    cat $far_dir/wav_raw.scp | awk '{printf("%s sox -t wav  %s -r 16000 -b 16 -c 1 -t wav  - |\n", $1, $2)}'  > $far_dir/wav.scp


    python local/alimeeting_process_overlap_force.py  --path $far_dir \
        --no-overlap false --mars True \
        --overlap_length 0.8 --max_length 7

    cat $far_dir/text_all | local/text_normalize.pl | local/text_format.pl | sort -u > $far_dir/text
    utils/filter_scp.pl -f 1 $far_dir/text $far_dir/utt2spk_all | sort -u > $far_dir/utt2spk
    #sed -e 's/ [a-z,A-Z,_,0-9,-]\+SPK/ SPK/'  $far_dir/utt2spk_old >$far_dir/utt2spk
    
    utils/utt2spk_to_spk2utt.pl $far_dir/utt2spk > $far_dir/spk2utt
    utils/filter_scp.pl -f 1 $far_dir/text $far_dir/segments_all | sort -u > $far_dir/segments
    sed -e 's/SRC/$/g' $far_dir/text> $far_dir/tmp1
    sed -e 's/ $//g' $far_dir/tmp1> $far_dir/tmp2
    sed -e 's/！//g' $far_dir/tmp2> $far_dir/tmp3
    sed -e 's/？//g' $far_dir/tmp3> $far_dir/tmp4
    sed -e 's/(\~)//g' $far_dir/tmp4> $far_dir/tmp5
    sed -e 's/(SIL)//g' $far_dir/tmp5> $far_dir/tmp6
    sed -e 's/(\/OVERLAP)//g' $far_dir/tmp6> $far_dir/text
fi


if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ]; then
    log "stage 3: finali data process"
    /Work21/2021/luhaoyu/espnet/egs2/AliMeeting/asr/utils/back/fix_data_dir.sh $near_dir
    /Work21/2021/luhaoyu/espnet/egs2/AliMeeting/asr/utils/back/fix_data_dir.sh $far_dir
    /Work21/2021/luhaoyu/espnet/egs2/AliMeeting/asr/utils/back/copy_data_dir.sh --utt-prefix ${tgt}-near- --spk-prefix ${tgt}-near- \
        $near_dir data/${tgt}_Ali_near
    /Work21/2021/luhaoyu/espnet/egs2/AliMeeting/asr/utils/back/copy_data_dir.sh --utt-prefix ${tgt}-far- --spk-prefix ${tgt}-far- \
        $far_dir data/${tgt}_Ali_far

    # remove space in text
    for x in ${tgt}_Ali_near ${tgt}_Ali_far; do
        cp data/${x}/text data/${x}/text.org
        paste -d " " <(cut -f 1 -d" " data/${x}/text.org) <(cut -f 2- -d" " data/${x}/text.org | tr -d " ") \
        > data/${x}/text
        rm data/${x}/text.org
    done

    log "Successfully finished. [elapsed=${SECONDS}s]"
fi

