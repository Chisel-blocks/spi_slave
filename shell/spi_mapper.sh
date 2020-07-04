#!/usr/bin/env bash
help_f()
{
SCRIPTNAME="spi_mapper"
cat << EOF
${SCRIPTNAME} Release 1.0 (4.7.2020)
$(echo ${SCRIPTNAME} | tr [:upper:] [:lower:]) - automatic SPI bit stream mapper !
Written by Ilia Kempi

SYNOPSIS
$(echo ${SCRIPTNAME} | tr [:upper:] [:lower:]) -e [TOPLEVEL_ENTITY] -m [UNPACKED_MACRO_PATH] -i [SIGNAL_INDEX] [OPTIONS]
DESCRIPTION
   Maps the spi bits from master file into scala source

OPTIONS
    -w
        Working directory path. Default: current run directory
    -e
        Toplevel entity name 
    -m
        Path of installed analog macros (script assumes directory structure created by "release_cell.sh" & "import_macro_package.sh")
    -i
        Index file for all SPI signals, special syntax is required
    -s
        Toplevel scala source template (no spi bits assigned yet). Default: src/main/scala/<toplevel_entity>/<toplevel_entity>_nospi.scala
    -t
        Target scala source that will be overwritten w/ all spi bits assigned. Default: src/main/scala/<toplevel_entity>/<toplevel_entity>.scala
    -d
        Documentation directory. Default: spidoc/
    -f
        File name of PDF spi documentation. Default: spidoc
    -p
        Temporary file directory (stores digital module verilog definitions), removed in the end. Default: spi_mapper_tmp/
    -h 
        Print this help.
EOF
}

workdir=""
toplevel_entity=""
unpacked_macro_path=""
signal_index=""
toplevel_scala=""
target_scala=""
spidoc_dir=""
spidoc_fname=""
tmpdir=""

while getopts w:e:m:i:s:t:d:f:p:h opt
do
  case "$opt" in
    w) workdir=${OPTARG};; 
    e) toplevel_entity=${OPTARG};; 
    m) unpacked_macro_path=`readlink -f ${OPTARG}`;; 
    i) signal_index=`readlink -f ${OPTARG}`;; 
    s) toplevel_scala=${OPTARG};; 
    t) target_scala=${OPTARG};; 
    d) spidoc_dir=${OPTARG};; 
    f) spidoc_fname=${OPTARG};; 
    p) tmpdir=${OPTARG};; 
    h) help_f; exit 0;;
    \?) help_f;;
  esac
done

if [ -z "$toplevel_entity" ]; then
    echo "Toplevel entity name is not given"
    help_f;
    exit 0
fi

if [ -z "$unpacked_macro_path" ]; then
    echo "Unpacked macro path is not given"
    help_f;
    exit 0
fi

if [ -z "$signal_index" ]; then
    echo "SPI master index file is not given"
    help_f;
    exit 0
fi

if [ -z "$workdir" ]; then
    workdir=`pwd`
    echo "Working directory not set, assuming $workdir by default"
fi

if [ -z "$toplevel_scala" ]; then
    toplevel_scala="$workdir/src/main/scala/$toplevel_entity/${toplevel_entity}_nospi.scala"
    echo "Toplevel scala template path not set, assuming $toplevel_scala by default"
fi

if [ -z "$target_scala" ]; then
    target_scala="$workdir/src/main/scala/$toplevel_entity/${toplevel_entity}.scala"
    echo "Target scala path not set, assuming $target_scala by default"
fi

if [ -z "$spidoc_dir" ]; then
    spidoc_dir="$workdir/spidoc"
    echo "Documentation directory is not set, assuming $spidoc_dir by default"
fi

if [ -z "$spidoc_fname" ]; then
    spidoc_fname="spidoc"
    echo "Documentation filename is not set, assuming \" $spidoc_fname \" by default"
fi

if [ -z "$tmpdir" ]; then
    tmpdir="$workdir/spi_mapper_tmp"
    echo "Temporary directory path is not set, assuming $tmpdir by default"
fi

mkdir -p "$spidoc_dir"
mkdir -p "$tmpdir"
cat "$toplevel_scala" > "$target_scala"

default_comment="-"
module=""

modules=()
modules_digital=()
modules_config=()
modules_monitor=()
module_ctr=0
config_ctr=0
monitor_ctr=0

config_signals=()
config_start=()
config_stop=()
config_signals_endians=()
config_signals_modules=()
config_signals_default=()
config_signals_digital=()
comments_config=()

monitor_signals=()
monitor_start=()
monitor_stop=()
monitor_signals_endians=()
monitor_signals_modules=()
monitor_signals_expected=()
monitor_signals_digital=()
comments_monitor=()

while IFS= read -r line; do
    if [[ ${line// } == '#'* ]]; then
        continue
    elif [[ -z "$line" ]]; then
        continue
    elif [[ "$line" == "module:"* ]]; then
        module=${line#module:}
        echo "read module $module"
        if [[ "$module_ctr" > 0 ]]; then
            modules_config+=("$config_ctr")
            modules_monitor+=("$monitor_ctr")
            config_ctr=0
            monitor_ctr=0
        fi
        module_ctr=$((module_ctr+1))
        module_verilog="$unpacked_macro_path/$module/digital/verilog/$module.v"
        if [[ -f "$module_verilog" ]]; then
            modules_digital+=('0')
        else
            echo "WARNING: Can't find $module verilog in $unpacked_macro_path, looking for digital module instead."
            top_verilog="$workdir/verilog/${toplevel_entity}.v"
            digi_module_definition=$( cat "$top_verilog" | grep "module $module" )
            if [[ -z "$digi_module_definition" ]]; then
                echo "ERROR: Cant find module $module definition on any of known paths."
                echo "Aborting"
                exit 0
            else
                module_verilog_tmp="$tmpdir/${module}_tmp.v"
                module_verilog="$tmpdir/${module}_def.v"
                moddef=$( sed -n "/^module $module/,/)\;/{p;/)\;/q}" < "$top_verilog" )
                echo "$moddef" > "$module_verilog_tmp"
                cat "$module_verilog_tmp" | grep -o '^[^//]*' > "$module_verilog"
                rm -f "$module_verilog_tmp"
                modules_digital+=('1')
            fi
        fi
        modules+=("$module")
    elif [[ "$module_ctr" > 0 ]]; then
        if [[ "$line" == *"#"* ]]; then
            comment=$( cut -d "#" -f2 <<< "$line" )
            line=$( cut -d "#" -f1 <<< "$line" )
        else 
            comment="$default_comment"
        fi
        signal=$( echo $line | cut -d' ' -f1)
        endian=$( echo $line | cut -d' ' -f2)
        value=$( echo $line | cut -d' ' -f3)
        if [[ "$signal" == "$endian" || -z "$endian" ]]; then
            echo "WARNING: unknown or incomplete module signal entry : $line"
            continue
        else
            if [[ ${modules_digital[-1]} == '1' && "$signal" == *")" ]]; then 
                signal_num=$(sed 's/.*(\(.*\))/\1/' <<< $signal)
                signal_name=$(grep -o '^[^(]*' <<< $signal)
                signal_clean="${signal_name}_${signal_num}"
                signal_v="$signal_clean"
            else
                signal_v="$signal"
            fi
            signal_definition=$( cat $module_verilog | grep $signal_v )
            if [[ -z "$signal_definition" ]]; then
                echo "ERROR: Can't find signal $signal in $module_verilog"
                echo "Aborting"
                exit 0
            elif [[ "$signal_definition" == *"input"* ]]; then
                config_signals+=("$signal")
                config_signals_modules+=("$module")
                config_signals_endians+=("$endian")
                comments_config+=("$comment")
                if [[ -z "$value" ]]; then
                    echo "WARNING: config signal $signal of $module has no default value assigned, assuming 0 instead"
                    value=0
                fi
                config_signals_default+=("$value")
                config_ctr=$((config_ctr+1))
                config_signals_digital+=(${modules_digital[-1]})
            elif [[ "$signal_definition" == *"output"* ]]; then
                monitor_signals+=("$signal")
                monitor_signals_modules+=("$module")
                monitor_signals_endians+=("$endian")
                comments_monitor+=("$comment")
                if [[ -z "$value" ]]; then
                    echo "WARNING: monitor signal $signal of $module has no expected value assigned, assuming none"
                    value="-"
                fi
                monitor_signals_expected+=("$value")
                monitor_ctr=$((monitor_ctr+1))
                monitor_signals_digital+=(${modules_digital[-1]})
            else
                echo "ERROR: Can't find the direction of $signal in $module_verilog"
                echo "Aborting"
                exit 0
            fi
        fi
    fi
done < "$signal_index"
modules_config+=("$config_ctr")
modules_monitor+=("$monitor_ctr")

config_definition=$( cat "$toplevel_scala" | grep "val spi_config_manual_bits" )
monitor_definition=$( cat "$toplevel_scala" | grep "val spi_monitor_manual_bits" )
config_ptr=$( echo $config_definition | cut -d' ' -f4 )
monitor_ptr=$( echo $monitor_definition | cut -d' ' -f4 )

# this wipes all the scala crutches for spi bit width elaboration
sed -i "0,/val dummy_monitor_size/{/val dummy_monitor_size/d}" "$target_scala"
sed -i "0,/val dummy_config_width/{/val dummy_config_width/d}" "$target_scala"
sed -i "0,/val dummy_config_words/{/val dummy_config_words/d}" "$target_scala"
sed -i "0,/val spi_dummy_in/{/val spi_dummy_in/d}" "$target_scala"
sed -i "0,/val spi_dummy_out/{/val spi_dummy_out/d}" "$target_scala"
sed -i "0,/val ptr_incr_in/{/val ptr_incr_in/d}" "$target_scala"
sed -i "0,/var ptr_incr_out/{/var ptr_incr_out/d}" "$target_scala"
sed -i "0,/def elab_config/{/def elab_config/d}" "$target_scala"
sed -i "0,/def elab_monitor/{/def elab_monitor/d}" "$target_scala"
sed -i "0,/to dummy_monitor_size/{/to dummy_monitor_size/d}" "$target_scala"

config_ptr_relative=0
signal_ctr=0
for signal in ${config_signals[@]}; do
    module=${config_signals_modules[$signal_ctr]}
    if [[ ${config_signals_digital[$signal_ctr]} == '1' ]]; then
        module_verilog="$tmpdir/${module}_def.v"
        sed -i "0,/elab_config($module\.$signal)/{/elab_config($module\.$signal)/d}" "$target_scala"
    else
        module_verilog="$unpacked_macro_path/$module/digital/verilog/$module.v"
    fi
    if [[ ${config_signals_digital[$signal_ctr]} == '1' && "$signal" == *")" ]]; then 
        signal_num=$(sed 's/.*(\(.*\))/\1/' <<< $signal)
        signal_name=$(grep -o '^[^(]*' <<< $signal)
        signal_clean="${signal_name}_${signal_num}"
        signal_v="$signal_clean"
    else
        signal_v="$signal"
    fi
    signal_definition=$( cat $module_verilog | grep $signal_v )
    if [[ "$signal_definition" == *"["* ]]; then
        endpart=${signal_definition%\:*}
        step=${endpart#*\[}
        start_ptr=$config_ptr
        stop_ptr=$((start_ptr+step))
        config_ptr=$((stop_ptr+1))
        config_ptr_relative=$((config_ptr_relative+step+1))
        #                           123456
        sed -i "/.*new $module.*/a \      $module\.$signal\:\=spi_slave.config_out($stop_ptr,$start_ptr)\.asTypeOf($module\.$signal\.cloneType)" "$target_scala"
        config_start+=("$start_ptr")
        config_stop+=("$stop_ptr")
    else
        #                           123456
        sed -i "/.*new $module.*/a \      $module\.$signal\:\=spi_slave.config_out($config_ptr)\.asTypeOf($module\.$signal\.cloneType)" "$target_scala"
        config_ptr=$((config_ptr+1))
        config_ptr_relative=$((config_ptr_relative+1))
        config_start+=("$config_ptr")
        config_stop+=("$config_ptr")
    fi
    signal_ctr=$((signal_ctr+1))
done
echo "Total of $config_ptr_relative SPI config register bits written for $signal_ctr signals"

signal_ctr=0
monitor_ptr_relative=0
for signal in ${monitor_signals[@]}; do
    module=${monitor_signals_modules[$signal_ctr]}
    if [[ ${monitor_signals_digital[$signal_ctr]} == '1' ]]; then
        module_verilog="$tmpdir/${module}_def.v"
        sed -i "0,/elab_monitor($module\.$signal)/{/elab_monitor($module\.$signal)/d}" "$target_scala"
    else
        module_verilog="$unpacked_macro_path/$module/digital/verilog/$module.v"
    fi
    if [[ ${monitor_signals_digital[$signal_ctr]} == '1' && "$signal" == *")" ]]; then 
        signal_num=$(sed 's/.*(\(.*\))/\1/' <<< $signal)
        signal_name=$(grep -o '^[^(]*' <<< $signal)
        signal_clean="${signal_name}_${signal_num}"
        signal_v="$signal_clean"
    else
        signal_v="$signal"
    fi
    signal_definition=$( cat $module_verilog | grep $signal_v )
    if [[ "$signal_definition" == *"["* ]]; then
        endpart=${signal_definition%\:*}
        step=${endpart#*\[}
        start_ptr=$monitor_ptr
        stop_ptr=$((start_ptr+step))
        monitor_ptr=$((stop_ptr+1))
        monitor_ptr_relative=$((monitor_ptr_relative+step+1))
        #                           123456
        sed -i "/.*new $module.*/a \      assign_monitor($module\.$signal,$stop_ptr,$start_ptr)" "$target_scala"
        monitor_start+=("$start_ptr")
        monitor_stop+=("$stop_ptr")
    else
        monitor_start+=("$monitor_ptr")
        monitor_stop+=("$monitor_ptr")
        #                           123456
        sed -i "/.*new $module.*/a \      assign_monitor($module\.$signal,$stop_ptr,$start_ptr)" "$target_scala"
        monitor_ptr=$((monitor_ptr+1))
        monitor_ptr_relative=$((monitor_ptr_relative+1))
    fi
    signal_ctr=$((signal_ctr+1))
done
echo "Total of $monitor_ptr_relative SPI monitor register bits written for $signal_ctr signals"

#                                           1234
sed -i "s/.*val spi_config_automap_bits =.*/    val spi_config_automap_bits \= $config_ptr_relative/" "$target_scala"
#                                            1234
sed -i "s/.*val spi_monitor_automap_bits =.*/    val spi_monitor_automap_bits \= $monitor_ptr_relative/" "$target_scala"

spidoc="$spidoc_dir/${spidoc_fname}.tex"
top_escaped=$( echo "$toplevel_entity" | sed 's/_/\\_/g' )

cat << EOF > "$spidoc"
\documentclass{article}
\usepackage[landscape,a4paper,margin=1in]{geometry}
\usepackage{longtable}
\title{$top_escaped SPI bitstream reference}
\author{Auto-generated by $USER}
\begin{document}
\maketitle
EOF

for m in "${!modules[@]}"; do
    module="${modules[$m]}"
    if [[ "${modules_digital[$m]}" == '1' ]]; then
        module_type="digital"
    else
        module_type="analog"
    fi
    module_escaped=$( echo "$module" | sed 's/_/\\_/g' )
    echo "\section{Module $module_escaped (${module_type})}" >> "$spidoc"
    echo "\subsection{$module_escaped Config register bits}" >> "$spidoc"
    if [[ "${modules_config[$m]}" > 0 ]]; then
        echo "\begin{center}" >> "$spidoc"
        echo "\begin{longtable}{|l|l|l|l|l|l|l|l|}" >> "$spidoc"
        echo "    \hline" >> "$spidoc"
        echo "    Signal name & Endianness & Length & MSB & LSB & Max value & Default value & Comment \\\\" >> "$spidoc"
        echo "    \hline" >> "$spidoc"
        for i in "${!config_signals[@]}"; do 
            if [[ "${config_signals_modules[$i]}" == "$module" ]]; then
                signal_escaped=$( echo "${config_signals[$i]}" | sed 's/_/\\_/g' )
                start_ptr="${config_start[$i]}"
                stop_ptr="${config_stop[$i]}"
                signal_length=$(( stop_ptr - start_ptr ))
                signal_length=$(( signal_length + 1 ))
                max_value=$(( 2 ** signal_length - 1 ))
                if [[ "${config_signals_endians[$i]}" == 'L' ]]; then
                    endian="Little"
                else
                    endian="Big"
                fi
                #     1234
                echo "    $signal_escaped & $endian & $signal_length & $stop_ptr & $start_ptr & $max_value & ${config_signals_default[$i]} & ${comments_config[$i]} \\\\" >> "$spidoc"
            fi
        done
        echo "    \hline" >> "$spidoc"
        echo "\end{longtable}" >> "$spidoc"
        echo "\end{center}" >> "$spidoc"
    else
        echo "Module $module_escaped doesn't have config SPI bits assigned." >> "$spidoc"
    fi
    echo "\subsection{$module_escaped Monitor register bits}" >> "$spidoc"
    if [[ "${modules_monitor[$m]}" > 0 ]]; then
        echo "\begin{center}" >> "$spidoc"
        echo "\begin{longtable}{|l|l|l|l|l|l|l|l|}" >> "$spidoc"
        echo "    \hline" >> "$spidoc"
        echo "    Signal name & Endianness & Length & MSB & LSB & Max value & Expected value & Comment \\\\" >> "$spidoc"
        echo "    \hline" >> "$spidoc"
        for i in "${!monitor_signals[@]}"; do 
            if [[ "${monitor_signals_modules[$i]}" == "$module" ]]; then
                signal_escaped=$( echo "${monitor_signals[$i]}" | sed 's/_/\\_/g' )
                start_ptr="${monitor_start[$i]}"
                stop_ptr="${monitor_stop[$i]}"
                signal_length=$(( stop_ptr - start_ptr ))
                max_value=$(( 2 ** signal_length ))
                if [[ "${monitor_signals_endians[$i]}" == 'L' ]]; then
                    endian="Little"
                else
                    endian="Big"
                fi
                #     1234
                echo "    $signal_escaped & $endian & $signal_length & $stop_ptr & $start_ptr & $max_value & ${monitor_signals_expected[$i]} & ${comments_monitor[$i]} \\\\" >> "$spidoc"
            fi
        done
        echo "    \hline" >> "$spidoc"
        echo "\end{longtable}" >> "$spidoc"
        echo "\end{center}" >> "$spidoc"
    else
        echo "Module $module_escaped doesn't have monitor SPI bits assigned." >> "$spidoc"
    fi
done
echo "\end{document}" >> "$spidoc"

cd "$spidoc_dir"
pdflatex "${spidoc_fname}.tex"
rm -f "${spidoc_fname}.tex"
rm -f "${spidoc_fname}.aux" "${spidoc_fname}.log" 
cd -
rm -rf "$tmpdir"

echo "Complete"
