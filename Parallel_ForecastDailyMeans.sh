#!/bin/bash
#shell script calculate and to save the daily means of the forecast period
#of the CAMS43 aerosol alert forcast
#for the usage with gnu parallel
#
#as basis the files found in ${InterpolateOutDir} are used
#wich have been inperpolated to a common grid
#
#The output is the daily file for each forecast

SAVEIFS=$IFS
#IFS=$(echo -en "\n\b")

if [ $# -lt 2 ]
	then echo "usage: ${0} <AerocomVar> <MaccVar>"
	exit 1
fi

AerocomVar=${1}
MaccVar=${2}

function WaitForFile {
	#wait up to 10 seconds for a file to appear
	(( counter=0 ))
	WaitFile="${1}"
	while [ ! -f "${WaitFile}" ]
		do echo "waiting for ${WaitFile} to appear ${counter}"
		sleep 1
		(( counter+=1 ))
		if [ $counter -gt 10 ]
			then return 1
		fi
	done
	return 0
}


#load constants
set -x
echo ${CAMS43AlertHome}
if [ -z ${CAMS43AlertHome} ]
	then . /home/aerocom/bin/Constants.sh
else
	. "${CAMS43AlertHome}/Constants.sh"
fi
#honour $NSLOTS from GridEngine
if [ ! -z ${NSLOTS} ]
	then
	SlotsToUse=${NSLOTS}
fi
set +x
set -x
UUID=`uuidgen`
echo "PPID: $PPID"
NcwaFile="${DailyCacheDir}/ncwa_${MaccVar}_${StartYear}_${UUID}_${Hostname}.run"
NcecatFile="${DailyCacheDir}/ncecat_${MaccVar}_${StartYear}_${UUID}_${Hostname}.run"
#rmfile="${DailyCacheDir}/remove_${MaccVar}_${StartYear}_${UUID}_${Hostname}.run"
cdoFile="${DailyCacheDir}/cdo_${MaccVar}_${StartYear}_${UUID}_${Hostname}.run"
ncksFile="${DailyCacheDir}/ncks_${MaccVar}_${StartYear}_${UUID}_${Hostname}.run"
ncattedFile="${DailyCacheDir}/ncatted_${MaccVar}_${StartYear}_${UUID}_${Hostname}.run"
ncap2File="${DailyCacheDir}/ncap2_${MaccVar}_${StartYear}_${UUID}_${Hostname}.run"
ncwaLateFile="${DailyCacheDir}/ncwa_late_${MaccVar}_${StartYear}_${UUID}_${Hostname}.run"
set +x

NCWA=`which ncwa`
NCECAT=`which ncecat`
CDO=`which cdo`
NCKS_=`which ncks`
NCATTED=`which ncatted`
NCAP2=`which ncap2`

SortTempFile="${DailyCacheDir}/sort_${UUID}.tmp"

rm -f ${NcwaFile} ${NcecatFile} ${cdoFile} ${ncksFile} ${ncattedFile} ${ncap2File} ${ncwaLateFile}

#different stages to divide script in parts for testing
Stage1Flag=1
Stage2Flag=1
RemoveFlag=1

if [ ${Stage1Flag} -gt 0 ]
	then
	declare -a NcwaList NcecatList cdoList

	if [ ${EnableDataCachingFlag} -eq 0 ] #caching is disabled
		then 
		DirsToWorkOn=(`find ${InterpolateOutDir} -mindepth 1 -maxdepth 1 -type d | grep -e ${StartYear} | grep  -v 12$ | sort`)
	else
		DirsToWorkOn=(`find ${InterpolateOutDir} -mindepth 1 -maxdepth 1 -type d -newermt "${MaxDaysToSearchForData} days ago"| sort`)
	fi
	#for DayDirs in `find ${InterpolateOutDir} -mindepth 1 -maxdepth 1 -type d | grep -e "${StartYear}010[1-2]" | grep  -v 12$ | sort`
	for DayDirs in ${DirsToWorkOn[@]}
		do echo ${DayDirs}

		echo "Number of elements in DirsToWorkOn ${#DirsToWorkOn[@]}"
		exit
		FileDayString=`echo ${DayDirs} | rev | cut -d/ -f1 | rev | cut -c1-8`
		#put the whole forecast period in one file so that we can use cdo for daily mean calculation
		HourlyFile="${DailyCacheDir}/${FileDayString}_${MaccVar}_hourly.nc"
		DailyFile="${DailyCacheDir}/${FileDayString}_${MaccVar}_daily.nc"
		#echo ${HourlyFile} >> "${rmfile}"
		#echo ${DailyFile} >> "${rmfile}"
		#test if  ${DailyFile} exists. If yes, don't recreate it to save time
		#ERRORPRONE!
		FileFoundFlag=0
		if [[ ! -f ${DailyFile} ]]
			then
			FileFoundFlag=1
			DayFileArr=`find ${DayDirs}/ -name z_cams_c_*_${StartYear}*_fc_*_${MaccVar}.nc -print | sort`
			if [[ ! -n ${DayFileArr} ]]
				then echo "no files in directory ${DayDirs} found!"
				continue
			fi
			#for DayFile in `find ${DayDirs}/ -name z_cams_c_ecmf_${StartYear}*_${MaccVar}.nc | sort`
			for DayFile in ${DayFileArr[*]}
				do #echo ${DayFile}
				FileHour=`basename ${DayFile} | cut -d_ -f9`
				FileDayString=`basename ${DayFile} | cut -d_ -f5 | cut -c1-8`
				newfile="${DailyCacheDir}/${FileDayString}_${MaccVar}_${FileHour}.nc"
				echo ${newfile} >> "${rmfile}"
				#get rid of the time dimension and put the file in DailyCacheDir
				echo "ncwa -7 -a time -O -o ${newfile} ${DayFile}" >> "${NcwaFile}"
				NcwaList+=("ncwa -7 -a time -O -o ${newfile} ${DayFile}")
			done
			#put the whole forecast period in one file so that we can use cdo for daily mean calculation
			#HourlyFile="${DailyCacheDir}/${FileDayString}_hourly.nc"
			#DailyFile="${DailyCacheDir}/${FileDayString}_daily.nc"
			#ncecat -O -u time -n 121,3,1 ${DailyCacheDir}/${FileDayString}_*.nc ${HourlyFile}
			#THERE MIGHT NOT ALWAYS BE 121 TIME STEPS TO WORK ON
			#MAYBE CONSIDER THAT?
			echo "ncecat -7 -O -u time -n 121,3,1 ${DailyCacheDir}/${FileDayString}_${MaccVar}_???.nc ${HourlyFile}" >> "${NcecatFile}"
			NcecatList+=("ncecat -7 -O -u time -n 121,3,1 ${DailyCacheDir}/${FileDayString}_${MaccVar}_???.nc ${HourlyFile}")
			#set +x
			#calculate daily mean using cdo
			echo "cdo -f nc4c -O daymean ${HourlyFile} ${DailyFile}" >> "${cdoFile}"
			cdoList+=("cdo -f nc4c -O daymean ${HourlyFile} ${DailyFile}")
		fi
	done

	if [ ${FileFoundFlag} -gt 0 ]
		then
		set -x
		WaitForFile "${NcwaFile}"
		echo Starting parallel for ncwa...
		/usr/bin/parallel --version
		#printf "%s\n" "${NcwaList[@]}" | /usr/bin/parallel --verbose -j ${SlotsToUse}
		/usr/bin/parallel -vk -j ${SlotsToUse} -a "${NcwaFile}"
		set +x
		wait

		WaitForFile "${NcecatFile}"
		echo Starting parallel for ncecat...
		#printf "%s\n" "${NcecatList[@]}" | parallel -j ${SlotsToUse} -v
		/usr/bin/parallel -vk -j ${SlotsToUse} -a "${NcecatFile}"
		wait

		WaitForFile "${cdoFile}"
		echo Starting parallel for cdo...
		#printf "%s\n" "${cdoList[@]}" | parallel -j ${SlotsToUse} -v
		#/usr/bin/parallel --verbose -j ${SlotsToUse} < "${cdoFile}"
		/usr/bin/parallel -vk -j ${SlotsToUse} -a "${cdoFile}"
		wait

		unset NcwaList NcecatList cdoList
	fi

	rm -f ${DailyCacheDir}/${StartYear}*_${MaccVar}_???.nc
	rm -f ${DailyCacheDir}/${StartYear}*_${MaccVar}_hourly.nc
fi

######################################################################

if [ ${Stage2Flag} -gt 0 ]
	then
	#set -x
	declare -a ncksList ncattedList ncap2List ncwaLateList
	#for DayDirs in `find ${InterpolateOutDir} -mindepth 1 -maxdepth 1 -type d | grep -e ${StartYear} | grep  -v 12$ | sort`
	#for DayDirs in `find ${InterpolateOutDir} -mindepth 1 -maxdepth 1 -type d | grep -e "${StartYear}0101" | grep  -v 12$ | sort`
	for DailyFile in `find ${DailyCacheDir} -type f -name "*_${MaccVar}_daily.nc" -newermt "${MaxDaysToSearchForData} days ago"| sort`
		do echo ${DailyFile}
		#echo ${DayDirs}
		FileDayString=`basename ${DailyFile} | cut -d_ -f1 `
		
		#FileDayString=`echo ${DayDirs} | rev | cut -d/ -f1 | rev | cut -c1-8`
		#put the whole forecast period in one file so that we can use cdo for daily mean calculation
		#DailyFile="${TempDir}/${FileDayString}_${MaccVar}_daily.nc"
		#now rip the DailyFile apart to make a yearly time series
		(( StartTimeStep=1 ))
		(( EndTimeStep=${StartTimeStep}+1 ))

		#FileTSNo=`ncks -m ${DailyFile} -v time | grep "time dimension 0" | cut -d, -f 2 | cut -d= -f2 | cut '-d ' -f2`
		FileTSNo=`${NCKS[*]} -m ${DailyFile} -v time | grep "time dimension 0" | cut -d, -f 2 | cut -d= -f2 | cut '-d ' -f2`
		#get the actual times from the netcdf file to avoid errors
		TimeString=`ncdump -v time -i -l 4096 ${DailyFile} | grep 'time = "'| sed -e 's/^ time = //g' -e 's/ ;$//g' -e 's/\", \"/,/g' -e 's/\"//g'`
		#echo ${TimeString}
		#the time string looks e.g. like this now: 
		#"2016-01-01T23,2016-01-02T23,2016-01-03T23,2016-01-04T23,2016-01-05T23,2016-01-06"
		#Please note that this has to be done each time since the logic of doing that only for the time steps needed
		#is not that easy to program (there's 6 days in each forecast)
		OldIFS=${IFS}
		IFS=","
		for c_Temp in ${TimeString}
			do echo ${c_Temp}
			datestring=`echo ${c_Temp} | cut -dT -f1`
			DOY=`date -d ${datestring} '+%j'`
			DayFile="${DailyCacheDir}/Day_${StartYear}_${MaccVar}_${DOY}.nc"
			#ncks -4 -L 5 -F -O -d time,${StartTimeStep},${StartTimeStep} ${DailyFile} ${DayFile}
			echo "ncks -7 -F -O -d time,${StartTimeStep} ${DailyFile} ${DayFile}" >> "${ncksFile}"
			ncksList+=("ncks -7 -F -O -d time,${StartTimeStep} ${DailyFile} ${DayFile}")

			temp="units,time,o,c,days since ${StartYear}-1-1 0:0:0"
			echo "ncatted -O -a '${temp}' ${DayFile}" >> "${ncattedFile}"
			ncattedList+=("ncatted -O -a '${temp}' ${DayFile}")

			temp="time(:)=${DOY}-1"
			echo "ncap2 -7 -o ${DayFile} -O -s '${temp}' ${DayFile} " >> "${ncap2File}"
			ncap2List+=("ncap2 -7 -o ${DayFile} -O -s '${temp}' ${DayFile} ")

			#remove the time dimension created by cdo
			echo "ncwa -7 -a time -O -o ${DayFile} ${DayFile}" >> "${ncwaLateFile}"
			ncwaLateList+=("ncwa -7 -a time -O -o ${DayFile} ${DayFile}")

			(( StartTimeStep = ${StartTimeStep} + 1 ))
		done
		IFS=${OldIFS}
	done
	echo "${ncksFile}"
	#sort the commands reversely to avoid working on the same file at the same time
	#and to make sure that the analysis data file is always used if it exists
	echo Starting parallel for ncks...
	WaitForFile "${ncksFile}"
	sort -r "${ncksFile}" > "${SortTempFile}"
	WaitForFile "${SortTempFile}"
	mv "${SortTempFile}" "${ncksFile}"
	/usr/bin/parallel -vk -j ${SlotsToUse} -a "${ncksFile}"
	#SAVEIFS=$IFS
	#IFS=$'\n' ncksList=($(sort <<<"${ncksList[*]}"))
	#IFS=$SAVEIFS
	#( printf "%s\n" "${ncksList[@]}" | parallel -j ${SlotsToUse} -v ; wait )
	wait

	#remove duplicates in the command list to save time
	echo Starting parallel for ncatted...
	WaitForFile "${ncattedFile}"
	sort -u "${ncattedFile}" > "${SortTempFile}"
	WaitForFile "${SortTempFile}"
	/usr/bin/parallel -vk -j ${SlotsToUse} -a "${SortTempFile}"
	wait

	echo Starting parallel for ncap2...
	WaitForFile "${ncap2File}"
	sort -u "${ncap2File}" > "${SortTempFile}"
	WaitForFile "${SortTempFile}"
	/usr/bin/parallel -vk -j ${SlotsToUse} -a "${SortTempFile}"
	wait

	echo Starting parallel for ncwa...
	WaitForFile "${ncwaLateFile}"
	sort -u "${ncwaLateFile}" > "${SortTempFile}"
	WaitForFile "${SortTempFile}"
	/usr/bin/parallel -vk -j ${SlotsToUse} -a "${SortTempFile}"
	wait
	unset  ncksList ncattedList ncap2List ncwaLateList
fi


if [ ${RemoveFlag} -gt 0 ]
	then
	rm -f ${DailyCacheDir}/Day_${MaccVar}*.nc 
	#rm -f ${NcwaFile} ${NcecatFile} ${rmfile} ${cdoFile} ${ncksFile} ${ncattedFile} ${ncap2File} ${ncwaLateFile} ${SortTempFile}
fi	
date=`date`
echo "$*" finished at ${date}

IFS=$SAVEIFS
exit 0
