%% run_overnight_JND_BCI_master_v1.m
% Master runner for the overnight JND-informed BCI analyses.

clear; clc; close all;
THIS_DIR = fileparts(mfilename('fullpath'));
ANALYSIS_ROOT = 'C:\MSI\oscillation\ternus AV BCI\analysis0906';
OUT_DIR = fullfile(ANALYSIS_ROOT,'Analysis_Output_v4_R2_070','Overnight_JND_BCI_v1');
if ~exist(OUT_DIR,'dir'), mkdir(OUT_DIR); end

MASTER = fullfile(OUT_DIR,'OVERNIGHT_MASTER_SUMMARY.txt');
if exist(MASTER,'file'), delete(MASTER); end
diary(MASTER); diary on;
cleanupDiary = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('============================================================\n');
fprintf(' OVERNIGHT JND-INFORMED BCI MASTER v1\n');
fprintf(' Started: %s\n',datestr(now));
fprintf('============================================================\n\n');

allTic=tic;

fprintf('\n******** STAGE 1 / 3: REAL DATA FITS ********\n');
run(fullfile(THIS_DIR,'stage1_realfit_JND_vs_Free_v1.m'));
diary(MASTER); diary on;

fprintf('\n******** STAGE 2 / 3: REPEATED RECOVERY ********\n');
run(fullfile(THIS_DIR,'stage2_repeated_JND_recovery_v1.m'));
diary(MASTER); diary on;

fprintf('\n******** STAGE 3 / 3: TRIAL-COUNT RECOVERY ********\n');
run(fullfile(THIS_DIR,'stage3_trialcount_MA_recovery_v1.m'));
diary(MASTER); diary on;

fprintf('\n============================================================\n');
fprintf(' OVERNIGHT MASTER COMPLETE\n');
fprintf(' Total elapsed: %s\n',localFmtTime(toc(allTic)));
fprintf(' Finished: %s\n',datestr(now));
fprintf(' Output: %s\n',OUT_DIR);
fprintf('============================================================\n');
diary off;

function s=localFmtTime(sec)
sec=round(sec);
h=floor(sec/3600); m=floor(mod(sec,3600)/60); ss=mod(sec,60);
s=sprintf('%02d:%02d:%02d',h,m,ss);
end
