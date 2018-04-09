task SmartSeq2SingleCellTask {

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
  String docker

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
  }

  command {
    echo "Task1"
    echo "String: "${stranded}
    echo "String: "${genome_ref_fasta}
    echo "String: "${rrna_intervals}
    echo "String: "${ref_flat}
    echo "String: "${hisat2_ref}
    echo "String: "${hisat2_trans_ref}
    echo "String: "${rsem_genome}
    echo "String: "${ref_name}
    echo "String: "${ref_trans_name}
    echo "String: "${gtf_file}

    python <<CODE

    chars = """SmartSeq2!"""
    print(chars)

    CODE
  }

  runtime {
    docker: docker
    memory: "100 MB"
    disks: "local-disk 10 HDD"
    cpu: "1"
    preemptible: 5
  }

  output {
    String smartseq2singlecelltask_output_a = "smartseq2singlecelltask_output_a"
    String smartseq2singlecelltask_output_b = "smartseq2singlecelltask_output_b"
    String smartseq2singlecelltask_output_c = "smartseq2singlecelltask_output_c"
    String smartseq2singlecelltask_output_d = "smartseq2singlecelltask_output_d"
  }
}