# prepare.smk — stage raw T1w / FLAIR / CBF into a BIDS layout and the MELD
# input tree. Pure host-side file ops (no container).
rule prepare:
    input:
        t1=lambda wc: SAMPLES[wc.sub]["t1w"],
        cbf=lambda wc: SAMPLES[wc.sub]["cbf"],
    output:
        t1=meld_input_t1("{sub}"),
        cbf=cbf_staged("{sub}"),
    params:
        ses=lambda wc: SAMPLES[wc.sub]["session"],
        flair=lambda wc: SAMPLES[wc.sub]["flair"],
        data=DATA,
        work=WORK,
    resources:
        mem_mb=res("prepare", "mem_mb", 4000),
        runtime=res("prepare", "runtime", 20),
        cpus_per_task=res("prepare", "cpus_per_task", 1),
    run:
        import os
        import shutil

        sub, ses = wildcards.sub, params.ses
        anat = os.path.join(params.data, sub, ses, "anat")
        perf = os.path.join(params.data, sub, ses, "perf")
        os.makedirs(anat, exist_ok=True)
        os.makedirs(perf, exist_ok=True)
        os.makedirs(os.path.dirname(output.t1), exist_ok=True)
        os.makedirs(os.path.dirname(output.cbf), exist_ok=True)

        # MELD input tree (consumed by the meld rule inside the container)
        shutil.copyfile(input.t1, output.t1)
        shutil.copyfile(input.cbf, output.cbf)

        # BIDS-style staging copies (human-readable provenance)
        shutil.copyfile(input.t1, os.path.join(anat, f"{sub}_{ses}_T1w.nii.gz"))
        shutil.copyfile(input.cbf, os.path.join(perf, f"{sub}_{ses}_cbf.nii.gz"))

        # FLAIR is optional; MELD auto-detects it under input/<sub>/FLAIR/
        if params.flair and os.path.isfile(params.flair):
            fdir = os.path.join(params.work, "input", sub, "FLAIR")
            os.makedirs(fdir, exist_ok=True)
            shutil.copyfile(params.flair, os.path.join(fdir, f"{sub}_FLAIR.nii.gz"))
            shutil.copyfile(params.flair, os.path.join(anat, f"{sub}_{ses}_FLAIR.nii.gz"))
