# Ternus Audiovisual Bayesian Causal-Inference Project

This repository provides data and MATLAB analysis code for the study **“Causal inference and task dependent weighting in audiovisual Ternus perception.”** The study examines how auditory and visual Ternus sequences are organized across modalities, how temporal disparity relates to common-source judgments, and how Bayesian causal-inference models explain element/group motion reports.

**Authors:** Xiaoyi Jia and Lihan Chen  
**Affiliation:** School of Psychological and Cognitive Sciences, Peking University  
**Contact:** xiaoyi_jia@stu.pku.edu.cn  
**Repository:** https://github.com/atahake/ternus-audiovisual-bci

## Study overview

Participants completed auditory and visual baseline psychophysics and a fully crossed 7 × 7 audiovisual Ternus design. Auditory and visual interstimulus intervals (ISIs) ranged from 30 to 210 ms in 30-ms steps. In separate report blocks, participants reported element or group motion in the designated modality (AttendV or AttendA) and then judged whether the auditory and visual streams appeared to share a common source.

The primary analyses included 34 participants who completed the programmed design and met the prespecified baseline-fit criterion. Behavioral analyses examined common-source judgments, target- and distractor-stream timing effects, and associations with independently measured psychophysical sensitivity.

The computational analyses compared three observer strategies:

- **Model averaging (MA):** combines common-cause and separate-cause estimates according to the causal posterior.
- **Forced fusion (FF):** assumes a common cause.
- **Segregation (Seg):** assumes separate causes.

The project evaluates both a **Free** model family, in which auditory and visual latent uncertainty are estimated independently, and a **baseline-informed relative-uncertainty** family, which constrains the auditory-to-visual latent-noise ratio using the participant's baseline JND ratio while leaving the overall scale free. A baseline JND is a behavioral psychometric width and is **not** treated as a direct measurement of latent sensory noise. Model preference is interpreted alongside prediction overlap, model recovery, and parameter-recovery diagnostics; a winning information criterion alone is not evidence of a uniquely identified perceptual mechanism.

## Repository contents

The repository currently contains the following files and archives:

| File | Contents |
|---|---|
| `Data.zip` | De-identified behavioral data and associated data/analysis files for the study. |
| `Baseline_Psychometric_Curves.zip` | Baseline psychometric-curve materials. |
| `code.zip` | MATLAB analysis and Bayesian causal-inference model scripts, organized by analysis stage. |
| `DATA_DICTIONARY.md` | Overview of the data and model-output variables. |
| `REPRODUCTION_GUIDE.md` | Short guide to the analysis workflow and software environment. |
| `DATA_AND_CODE_AVAILABILITY.txt` | Data/code availability statement associated with the manuscript. |
| `CITATION.cff` | Citation metadata for this repository. |
| `LICENSE` | Repository license. |

### MATLAB code organization

After extracting `code.zip`, the included scripts are organized into these folders:

- `01_MAIN_PIPELINE/` — primary model-comparison pipeline (`run_BCI_model_comparison_v4.m`).
- `02_BCI_CORE/` — likelihood and response-distribution functions used by the observer models.
- `03_BEHAVIOR/` — empirical response summaries, model-prediction grids, baseline psychometric plots, and a reliability-aware random-slope check.
- `04_FREE_BCI_RECOVERY/` — recovery analyses for the unconstrained Free model family.
- `05_IDENTIFIABILITY/` — diagnostics of prediction overlap and MA–FF identifiability.
- `06_BASELINE_INFORMED_BCI/` — baseline-informed model fitting and recovery analyses.

The code archive includes the following main scripts: `run_BCI_model_comparison_v4.m`, `computeNegLL_AVTernus_v4.m`, `computeRespDistrib_AVTernus_v4.m`, `export_behavior_empirical_bins_v2.m`, `export_behavior_prediction_grids_v3.m`, `plot_baseline_psychometric_curves.m`, `run_reliability_random_slope_check.m`, `run_BCI_R2filtered_recovery_v4.m`, `diagnose_MA_FF_identifiability_v2.m`, `run_JND_BCI_v1.m`, and `run_JND_informed_BCI_recovery_v1.m`.

Experimental stimulus-presentation programs are not included in this repository.

## Software and setup

The analyses were developed with **MATLAB R2024**. Depending on the analysis being run, MATLAB functionality for numerical optimization and generalized linear mixed-effects models may be required.

1. Download or clone this repository.
2. Extract `Data.zip`, `Baseline_Psychometric_Curves.zip`, and `code.zip` into locations accessible to MATLAB.
3. Read `REPRODUCTION_GUIDE.md` and the comments at the top of the relevant scripts before running an analysis.
4. Check and update input/output paths for your local machine. Some scripts were developed in a Windows environment and may contain machine-specific absolute paths; they may need to be edited before they will run elsewhere.
5. Run the required scripts in the order appropriate to the analysis you wish to reproduce, starting with the primary model-comparison pipeline when reproducing the main model comparison. Recovery and identifiability analyses are separate, computationally intensive stages.

The scripts should not be assumed to run unchanged on every computer. Confirm that the input files referenced by each script are present and that output directories exist before launching a full recovery simulation.

## Analysis workflow

The analysis sequence follows the structure of the manuscript and supporting information:

1. Screen the sample and fit the unimodal auditory and visual baseline psychometric functions.
2. Analyze audiovisual behavioral responses, including common-source judgments and motion reports in AttendV and AttendA.
3. Fit and compare the Free MA, FF, and Seg observer models.
4. Evaluate model recovery, parameter recovery, and MA–FF prediction overlap to assess practical identifiability.
5. Fit the baseline-informed relative-uncertainty family and compare recovery with the Free family.
6. Inspect sensitivity and diagnostic analyses before interpreting model preference.

Trial-count simulations are diagnostic analyses of residual model ambiguity; they should not be interpreted as a recommendation that future experiments must collect a particular multiple of the original number of trials.

## Interpretation and reproducibility notes

- The physical audiovisual design is the same 7 × 7 ISI grid across participants; the grid is not adjusted online to individual PSEs.
- Baseline JNDs describe the widths of fitted behavioral transitions. Their use to constrain a latent uncertainty ratio is a model-linking assumption, not an established identity between JND and sensory noise.
- The baseline-informed model constrains relative auditory–visual uncertainty but leaves the absolute noise scale free.
- Recovery results are conditional on the candidate models, parameter ranges, and simulation settings tested. They support conclusions about practical identifiability within the tested model space, not global identifiability or proof that one strategy is the brain's unique mechanism.
- Reproduction may require adapting paths and output-directory settings to the local environment. Record any such changes when reporting reproduced results.

For details on variable definitions, consult `DATA_DICTIONARY.md`. For the manuscript's supporting methods, model specifications, and diagnostic analyses, consult the associated Supporting Information.

## Citation

If you use the data or code, please cite the associated manuscript:

> Jia, X., & Chen, L. *Causal inference and task dependent weighting in audiovisual Ternus perception.*

Please also cite this repository: https://github.com/atahake/ternus-audiovisual-bci

## Contact

For questions about the data or analysis code, contact Xiaoyi Jia at `xiaoyi_jia@stu.pku.edu.cn`.
