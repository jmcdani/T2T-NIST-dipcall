## Snakefile runs dipcall only, using docker container.  Dipcall utilizes whichever reference is specified in the samples.tsv file. 
## Dipcall parameters are default with expeception of using Chai minimap2 setting (line40 run_dipcall file).  
## This snakefile will be used to generate vcf, bed and bams for T2T variant_team work
## Run with command: caffeinate -s snakemake --use-conda --verbose -s Snakefile -k --cores 1
## Once pipeline has run print report: snakemake --report output/{prefix}/report_{prefix}.html -s Snakefile

##########################

## Import dependencies
import pandas as pd
from snakemake.utils import min_version

### set minimum snakemake version
min_version("5.18.0")

## Loading config file and sample sheet
configfile: "config.yaml"

## Read table of samples and set wildcard prefix and constraints
asm = pd.read_table(config["assemblies"]).set_index(["prefix"], drop = False)
ASM_prefix = list(set(asm["prefix"]))

wildcard_constraints:
    prefix="|".join(ASM_prefix)

rule all:
    input: 
        expand("output/{prefix}/{prefix}.mak", prefix = ASM_prefix), #for use with dipcall_makefile rule
        expand("output/{prefix}/{prefix}.dip.vcf.gz", prefix = ASM_prefix),
        expand("output/{prefix}/{prefix}.dip.bed", prefix = ASM_prefix),
        expand("output/{prefix}/{prefix}.hap1.bam", prefix = ASM_prefix),
        expand("output/{prefix}/{prefix}.hap2.bam", prefix = ASM_prefix),
        expand("output/{prefix}/{prefix}.dip.vcf.gz.tbi", prefix = ASM_prefix),
        expand("output/{prefix}/{prefix}.hap1.bam.bai", prefix = ASM_prefix),
        expand("output/{prefix}/{prefix}.hap2.bam.bai", prefix = ASM_prefix)

       
################################################################################
## Python functions to get assembly haplotypes and reference paths for alignment
################################################################################
def get_hap1(wildcards):
    #path=asm.loc[(wildcards.prefix), ["h1"]]
    path=asm.loc[(wildcards.prefix), "h1"]
    return(path)

def get_hap2(wildcards):
    #path = asm.loc[(wildcards.prefix), ["h2"]]
    path = asm.loc[(wildcards.prefix), "h2"]
    return(path)

def get_refPath(wildcards):
    path = asm.loc[(wildcards.prefix), ["refPath"]]
    return(path)

################################################################################
## Prepare makefile for dipcall
################################################################################
rule dipcall_makefile:
    input:
        h1=get_hap1,
        h2=get_hap2,
        path=get_refPath,
        par=config["par"]
    output: "output/{prefix}/{prefix}.mak"
    params: 
        prefix = "output/{prefix}/{prefix}"
    log: "output/{prefix}/{prefix}_dipcall_makefile.log"
    shell: """
        ## Getting path and file name info for docker command
        H1=$(basename {input.h1})
        H2=$(basename {input.h2})
        WD=$(pwd)
        ASMDIR1=$WD/$(dirname {input.h1})
        ASMDIR2=$WD/$(dirname {input.h2})
                                                
        docker run -it \
            -v $(pwd):/data \
            -v $ASMDIR1:/assem1 \
            -v $ASMDIR2:/assem2 \
            hap.py_docker:v0.3.12 /data/src/dipcall.kit/run-dipcall \
                    -x /data/{input.par} \
                    /data/{params.prefix} \
                    /data/{input.path} \
                    /assem1/$H1 \
                    /assem2/$H2 \
                    > {output}
            """

################################################################################
## Run dipcall using make. This is default dipcall with change to minimap2 param
## on line 40 of run_dipcall file
################################################################################

rule run_dipcall:
    input: 
        h1=get_hap1,
        h2=get_hap2,
        make="output/{prefix}/{prefix}.mak"
    output: 
        vcf="output/{prefix}/{prefix}.dip.vcf.gz",
        bed="output/{prefix}/{prefix}.dip.bed",
        bam1="output/{prefix}/{prefix}.hap1.bam",
        bam2="output/{prefix}/{prefix}.hap2.bam"
    log: "output/{prefix}/{prefix}_dipcall.log"
    shell: """
        H1=$(basename {input.h1})
        H2=$(basename {input.h2})
        WD=$(pwd)
        ASMDIR1=$WD/$(dirname {input.h1})
        ASMDIR2=$WD/$(dirname {input.h2})

        sudo docker run -it \
            -v $(pwd):/data \
            -v $ASMDIR1:/assem1 \
            -v $ASMDIR2:/assem2 \
            hap.py_docker:v0.3.12 make -j1 -f /data/{input.make}
    """

################################################################################
## Index Dipcall output files *.bam and *dip.vcf.gz
################################################################################

rule tabix:
    input: "output/{prefix}/{prefix}.dip.vcf.gz"
    output: "output/{prefix}/{prefix}.dip.vcf.gz.tbi"
    params:
        "-p vcf"
    log:
        "output/{prefix}/tabix_{prefix}.log"
    wrapper:
        "0.64.0/bio/tabix"

rule samtools_sort:
    input: "output/{prefix}/{prefix}.{hap}.bam"
    output: "output/{prefix}/{prefix}.{hap}.sorted.bam"
    wrapper:
        "0.64.0/bio/samtools/sort"

rule samtools_index:
    input: "output/{prefix}/{prefix}.{hap}.sorted.bam"
    output: "output/{prefix}/{prefix}.{hap}.bam.bai"
    wrapper:
        "0.64.0/bio/samtools/index"
