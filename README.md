# Ternus Audiovisual Bayesian Causal-Inference Project

This repository provides data and analysis materials for the study of audiovisual Ternus perception and Bayesian causal-inference (BCI) modeling.

## Authors and contact

- **Xiaoyi Jia**
- **Lihan Chen**
- School of Psychological and Cognitive Sciences, Peking University
- Contact: xiaoyi_jia@stu.pku.edu.cn

## Repository contents

The files currently available in the repository are listed below. The data and code are provided as ZIP archives in this version of the repository.

| File | Contents / purpose |
|---|---|
| `Data.zip` | De-identified behavioral and task data supplied for the analyses. See `DATA_DICTIONARY.md` for the available data descriptions. |
| `Baseline_Psychometric_Curves.zip` | Baseline psychometric-curve materials. |
| `code.zip` | MATLAB analysis code and model implementation files. |
| `CITATION.cff` | Citation metadata for this repository. |
| `DATA_DICTIONARY.md` | Description of the data categories and variables. |
| `REPRODUCTION_GUIDE.md` | Brief outline of the analysis workflow and software environment. |
| `DATA_AND_CODE_AVAILABILITY.txt` | Data and code availability statement associated with the project. |
| `LICENSE` | MIT license file. |

The archives are provided as uploaded; consult their contents and accompanying documentation before running analyses. The repository does not currently expose the code and data as browsable folder trees.

## Study overview

The project uses the Ternus display paradigm to investigate audiovisual temporal organization and apparent-motion judgments. The analysis includes baseline auditory and visual psychophysics, audiovisual behavioral analyses, Bayesian causal-inference observer models, model comparison, model-recovery and identifiability diagnostics, and a baseline-informed model.

The canonical analysis described in the manuscript includes 34 participants and an audiovisual design with auditory and visual interstimulus intervals varied independently across a 7 × 7 set of combinations. Refer to the manuscript and supplementary information for the precise inclusion criteria, task details, model specifications, and reported results.

## Model interpretation

The baseline-informed model uses baseline psychophysical sensitivity to constrain the **relative** auditory–visual uncertainty structure while leaving the overall scale free. Baseline JND values are not assumed to be numerically identical to latent sensory-noise parameters in the audiovisual observer.

Model comparison and recovery results should be interpreted conditional on the candidate models, parameterization, and simulated data-generating assumptions. They do not, by themselves, establish a unique perceptual or neural mechanism.

## Software and reproduction

The analysis code was developed for MATLAB R2024. The current `REPRODUCTION_GUIDE.md` provides the high-level workflow:

1. Baseline psychophysical analyses.
2. Audiovisual behavioral analyses.
3. Bayesian causal-inference model fitting.
4. Model recovery and identifiability analyses.
5. Baseline-informed uncertainty analyses.
6. Figure generation.

To begin:

1. Download and extract `Data.zip`, `Baseline_Psychometric_Curves.zip`, and `code.zip`.
2. Read `DATA_DICTIONARY.md` and `REPRODUCTION_GUIDE.md`.
3. Inspect the MATLAB scripts for required input files, toolbox dependencies, and output locations before running them.
4. Run analyses in the order required by their dependencies.

The stimulus-presentation programs are **not included** in the current repository. The complete analysis pipeline has not been certified here as a one-click reproduction workflow; users should verify the required dependencies and input paths in their local MATLAB environment.

## Data and code availability

The de-identified data and analysis materials available for this project are provided in the repository archives listed above. Experimental stimulus-presentation programs are not included in the current release.

## Citation

Please cite the associated manuscript when using these materials:

Jia, X., & Chen, L. *[Manuscript title to be added]*. [Publication details to be added when available.]

## License

See `LICENSE` for the repository license terms.
