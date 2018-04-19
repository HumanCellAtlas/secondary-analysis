import "SmartSeq2SingleCellTask.wdl" as SS2Task

workflow MockSmartSeq2SingleCell {
  meta {
    description: "Sample SmartSeq2 scRNA-Seq data workflow."
  }

  String genome_ref_fasta
  String gtf_file
  String rrna_intervals
  String ref_flat
  String hisat2_ref
  String hisat2_trans_ref
  String rsem_genome
  String ref_name
  String ref_trans_name
  String stranded
  String? opt_docker
  # runtime values
  String docker = select_first([opt_docker, "python:3.6-slim"])

  parameter_meta {
    gtf_file: "Description Placeholder"
    genome_ref_fasta: "Description Placeholder"
    rrna_intervals: "Description Placeholder"
    ref_flat: "Description Placeholder"
    hisat2_ref: "Description Placeholder"
    hisat2_trans_ref: "Description Placeholder"
    rsem_genome: "Description Placeholder"
    ref_name: "Description Placeholder"
    ref_trans_name: "Description Placeholder"
    stranded: "Description Placeholder"
    opt_docker: "optionally provide a docker to run in"
  }

  call SS2Task.SmartSeq2SingleCellTask {
    input:
      genome_ref_fasta = genome_ref_fasta,
      gtf_file = gtf_file,
      rrna_intervals = rrna_intervals,
      ref_flat = ref_flat,
      hisat2_ref = hisat2_ref,
      hisat2_trans_ref = hisat2_trans_ref,
      rsem_genome = rsem_genome,
      ref_name = ref_name,
      ref_trans_name = ref_trans_name,
      stranded = stranded,
      docker = docker
  }

  output {
    String mocksmartseq2singlecell_output_a = SmartSeq2SingleCellTask.smartseq2singlecelltask_output_a
    String mocksmartseq2singlecell_output_b = SmartSeq2SingleCellTask.smartseq2singlecelltask_output_b
    String mocksmartseq2singlecell_output_c = SmartSeq2SingleCellTask.smartseq2singlecelltask_output_c
    String mocksmartseq2singlecell_output_d = SmartSeq2SingleCellTask.smartseq2singlecelltask_output_d
  }
}
