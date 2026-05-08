#!/bin/bash
#BSUB -q milan
#BSUB -J probe_node
#BSUB -n 1
#BSUB -R "rusage[mem=1GB]"
#BSUB -M 1100MB
#BSUB -W 00:05
#BSUB -o probe_node_%J.out

echo "===== Node probe ========================="
echo "Date:        $(date)"
echo "Job ID:      ${LSB_JOBID}"
echo "Queue:       ${LSB_QUEUE}"
echo "Hostname:    $(hostname)"
echo ""
echo "--- CPU ---"
echo "Logical cores (nproc): $(nproc)"
lscpu | grep -E "^(Model name|Socket|Core|Thread|CPU\(s\))"
echo ""
echo "--- RAM ---"
free -h
echo ""
echo "--- Local disk (/tmp) ---"
df -h /tmp
echo "=========================================="
