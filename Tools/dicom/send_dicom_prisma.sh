#export DCMTK=/usr/cenir/src/dcmtk
#export LD_LIBRARY_PATH=$DCMTK/lib
export DCMDICTPATH=/export/data/opt/CENIR/dcmtk/dicom.dic

storescu -aet CENIR03  -aec IRM1_PRIM 192.168.6.1 104 $*
