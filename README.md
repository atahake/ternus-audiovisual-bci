# Ternus Audiovisual Bayesian Causal-Inference Project

**Authors:** Xiaoyi Jia and Lihan Chen  
**Affiliation:** School of Psychological and Cognitive Sciences, Peking University  
**Contact:** xiaoyi_jia@stu.pku.edu.cn

## Overview

This repository contains materials supporting a study of audiovisual temporal organization using the Ternus display paradigm and Bayesian causal-inference (BCI) observer models.

The study examines how auditory and visual temporal structure influences apparent-motion reports and common-cause judgments, and whether independently measured baseline psychophysical sensitivity can constrain the *relative* auditory–visual uncertainty structure in an audiovisual observer model.

## Repository contents

- `01_CODE/` — MATLAB analysis scripts and model implementations. See [`README_CODE.md`](01_CODE/README_CODE.md) for code-specific instructions.
- `02_RESULTS/` — analysis outputs, model-fitting results, recovery outputs, and tables, where included.
- `03_FIGURES/` — manuscript and supplementary figures, where included.
- `04_MANUSCRIPT/` — manuscript files, where included.
- `06_DOCUMENTATION/` — data dictionary, reproduction notes, and supporting documentation.
- Data archives or data folders — de-identified behavioral and baseline psychophysical data, if included in the public release.
- `Supporting_Information.pdf` — supplementary methods, figures, and tables, if included in the repository.

Folder names and availability may vary across repository versions. Consult the actual files in the current release; do not assume that every category above is populated.

## Study design and analysis

The canonical analysis uses 34 participants after applying the study's baseline psychometric quality-control criterion. The audiovisual task uses a 7 × 7 design in which auditory and visual interstimulus intervals (ISIs) are varied independently.

The analysis workflow includes:

1. Baseline auditory and visual psychophysical analyses.
2. Audiovisual behavioral analyses.
3. Unconstrained Bayesian causal-inference model fitting and model comparison.
4. Model-recovery and identifiability diagnostics, including model mimicry and parameter-recovery analyses.
5. A baseline-informed model that constrains relative auditory–visual uncertainty while leaving the absolute scale free.
6. Recovery, trial-count, and sensitivity analyses, where corresponding scripts and outputs are included.

## Important interpretation notes

- Baseline JND values are behavioral psychometric-width measures; they are not assumed to be numerically identical to latent sensory-noise parameters.
- The baseline-informed model uses baseline sensitivity to constrain the *relative* auditory–visual uncertainty structure. It does not establish that baseline JNDs directly equal the latent noise parameters in the audiovisual task.
- Model comparison and recovery results provide evidence conditional on the candidate models, parameterization, and simulated data-generating assumptions. They do not, by themselves, prove a unique neural or perceptual mechanism.

## Software

The analysis code was developed for MATLAB R2024. Required toolboxes and dependencies should be checked in the relevant scripts and in `01_CODE/README_CODE.md`.

## Reproducing analyses

1. Download or clone the repository.
2. Obtain the de-identified data files included in the public release.
3. Open MATLAB and set the repository root as the working directory.
4. Read `01_CODE/README_CODE.md` before running any script.
5. Run the relevant scripts in the documented order. Some analyses may depend on intermediate files produced by earlier steps.
6. Check each script's input paths and output locations before running it.

The scripts have undergone static review and path/documentation cleanup, but the complete pipeline has not yet been verified in a clean MATLAB environment. Do not interpret the repository as a guaranteed one-click reproduction until end-to-end execution has been tested.

## Data and code availability

De-identified behavioral data, baseline psychophysical measurements, analysis code, model implementations, and figure-generation scripts are available through this repository to the extent that the corresponding files are included in the public release.

Experimental stimulus-presentation programs are not included in the current release.

## Citation

Please cite the associated manuscript when using these materials:

Jia, X., & Chen, L. *[Manuscript title to be added]*. [Publication details to be added when available.]

## License

See the `LICENSE` file if one is included. If no license is present, reuse permissions have not yet been explicitly specified.
