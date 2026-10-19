%% export_behavior_empirical_bins_v2.m
% Export descriptive empirical summaries for Figure 2 from the completed
% Phase-2 trial table.
%
% IMPORTANT
%   - This script performs NO new inferential test.
%   - It does NOT refit the GLMEs.
%   - It does NOT remove any AV cells.
%   - Binning is for visualization only; all inferential conclusions remain
%     based on the continuous random-slope GLMEs already reported.
%
% Required:
%   Phase2_Analysis_Results_v4.mat
%       containing trialTable
%
% Expected trialTable variables from the completed reliability analysis:
%   SubjectCat, TaskCat, RespCausal, Dms30, LogJointPrecisionC
%
% Outputs:
%   Figure2A_Empirical_CausalByTask.csv
%   Figure2B_Empirical_CausalByPrecision.csv
%   Figure2_Empirical_Metadata.txt

clear; clc;

ROOT = 'C:\MSI\oscillation\ternus AV BCI\analysis0906';
OUT_DIR = fullfile(ROOT,'Publication_Figures_v2');
if ~exist(OUT_DIR,'dir'), mkdir(OUT_DIR); end

phase2File = findOne(ROOT,'Phase2_Analysis_Results_v4.mat');
baselineFile = findOne(ROOT,'Baseline_Psychometric_Summary.csv');

S = load(phase2File,'trialTable');
if ~isfield(S,'trialTable') || ~istable(S.trialTable)
    error('Phase2 MAT does not contain a MATLAB table named trialTable.');
end
T = S.trialTable;
BL = readtable(baselineFile,'TextType','string');

% The saved Phase-2 trialTable contains the original variables rather than
% the derived GLME variables Dms30 / LogJointPrecisionC. Reconstruct them
% exactly from the saved analysis quantities:
%   disparity = AbsPSECenteredDiff
%   joint precision = 1 / (JND_A^2 + JND_V^2)
%
% This is a descriptive export only and does not refit any model.
subject = string(T.Subject);
task    = string(T.Task);
resp    = double(T.RespCausal);
dms     = double(T.AbsPSECenteredDiff);

% Match baseline JNDs to Phase-2 subjects using stable numeric subject keys
% (handles the historical S06LY vs S06 naming discrepancy).
trialKeys = subjectKey(subject);
baseKeys  = subjectKey(BL.ID);

subjects = unique(subject,'stable');
subjKeys = subjectKey(subjects);

subjPrecRaw = nan(numel(subjects),1);
for is = 1:numel(subjects)
    key = subjKeys(is);
    ib = find(baseKeys==key);
    if numel(ib)~=1
        error('Expected one baseline row for %s; found %d.',subjects(is),numel(ib));
    end
    subjPrecRaw(is) = log(1/(BL.A_JND(ib)^2 + BL.V_JND(ib)^2));
end
meanPrec = mean(subjPrecRaw,'omitnan');
subjPrec = subjPrecRaw - meanPrec;

% Map centered subject-level precision back to trials.
precC = nan(height(T),1);
for is = 1:numel(subjects)
    precC(subject==subjects(is)) = subjPrec(is);
end

ok = isfinite(resp) & isfinite(dms) & isfinite(precC) & ...
     (task=="AttendV" | task=="AttendA");
subject=subject(ok); task=task(ok); resp=resp(ok); dms=dms(ok); precC=precC(ok);

if ~all(ismember(unique(resp),[0 1]))
    error('RespCausal is not coded 0/1 in trialTable; inspect before plotting.');
end

subjects = unique(subject,'stable');
if numel(subjects)~=34
    warning('Expected 34 subjects in trialTable, found %d.',numel(subjects));
end

% 30-ms descriptive bins, aligned with the experimental ISI step.
maxD = ceil(max(dms)/30)*30;
edges = 0:30:(maxD+30);
bin = discretize(dms,edges);

%% Figure 2A: empirical causal response by task and disparity
rows = {};
for tk = ["AttendV","AttendA"]
    for b = 1:(numel(edges)-1)
        sMeans=[]; sX=[]; nTrials=0;
        for is=1:numel(subjects)
            ix = subject==subjects(is) & task==tk & bin==b;
            if any(ix)
                sMeans(end+1,1)=mean(resp(ix)); %#ok<AGROW>
                sX(end+1,1)=mean(dms(ix)); %#ok<AGROW>
                nTrials=nTrials+nnz(ix);
            end
        end
        if numel(sMeans)>=3
            rows(end+1,:)={char(tk),b,mean(sX),mean(sMeans), ...
                std(sMeans)/sqrt(numel(sMeans)),numel(sMeans),nTrials}; %#ok<AGROW>
        end
    end
end
A = cell2table(rows,'VariableNames', ...
    {'Task','Bin','MeanDisparity_ms','MeanPCommon','SEM','NSubjects','NTrials'});
A.Task=string(A.Task);
writetable(A,fullfile(OUT_DIR,'Figure2A_Empirical_CausalByTask.csv'));

%% Figure 2B: lower vs higher precision descriptive quartiles
% Precision is subject-level. Use the lower and upper quartiles only for
% display; the inferential GLME uses precision continuously.
% Recompute from the filtered trial rows only to preserve subject order.
subjPrecPlot=nan(numel(subjects),1);
for is=1:numel(subjects)
    x=precC(subject==subjects(is));
    subjPrecPlot(is)=mean(x,'omitnan');
end
q=prctile(subjPrecPlot,[25 75]);
lowSubjects=subjects(subjPrecPlot<=q(1));
highSubjects=subjects(subjPrecPlot>=q(2));

rows = {};
levels=["Lower precision","Higher precision"];
groups={lowSubjects,highSubjects};
for ig=1:2
    gsubs=groups{ig};
    gp=mean(subjPrecPlot(ismember(subjects,gsubs)),'omitnan');
    for b=1:(numel(edges)-1)
        sMeans=[]; sX=[]; nTrials=0;
        for is=1:numel(gsubs)
            % Pool AttendV and AttendA within each participant to match the
            % task-averaged visualization in Figure 2B.
            ix = subject==gsubs(is) & bin==b;
            if any(ix)
                sMeans(end+1,1)=mean(resp(ix)); %#ok<AGROW>
                sX(end+1,1)=mean(dms(ix)); %#ok<AGROW>
                nTrials=nTrials+nnz(ix);
            end
        end
        if numel(sMeans)>=3
            rows(end+1,:)={char(levels(ig)),b,mean(sX),mean(sMeans), ...
                std(sMeans)/sqrt(numel(sMeans)),numel(sMeans),nTrials,gp}; %#ok<AGROW>
        end
    end
end
B = cell2table(rows,'VariableNames', ...
    {'PrecisionLevel','Bin','MeanDisparity_ms','MeanPCommon','SEM', ...
     'NSubjects','NTrials','GroupMeanLogJointPrecisionC'});
B.PrecisionLevel=string(B.PrecisionLevel);
writetable(B,fullfile(OUT_DIR,'Figure2B_Empirical_CausalByPrecision.csv'));

fid=fopen(fullfile(OUT_DIR,'Figure2_Empirical_Metadata.txt'),'w');
cleanup=onCleanup(@() fclose(fid));
fprintf(fid,'Descriptive empirical summaries only; no new inferential testing.\n');
fprintf(fid,'Phase2 source: %s\n',phase2File);
fprintf(fid,'Baseline source: %s\n',baselineFile);
fprintf(fid,'N subjects = %d\n',numel(subjects));
fprintf(fid,'30-ms visualization bins, range %.1f to %.1f ms.\n',min(dms),max(dms));
fprintf(fid,'Lower precision group: N=%d; threshold <= %.8f centered log precision.\n',numel(lowSubjects),q(1));
fprintf(fid,'Higher precision group: N=%d; threshold >= %.8f centered log precision.\n',numel(highSubjects),q(2));
fprintf(fid,'All statistical inference remains based on the continuous correlated-random-slope GLMEs.\n');

fprintf('\nDone. Empirical Figure-2 summaries written to:\n%s\n',OUT_DIR);

%% helpers
function p=findOne(rootDir,fileName)
    d=dir(fullfile(rootDir,'**',fileName));
    if isempty(d), error('Cannot find %s under %s',fileName,rootDir); end
    [~,ix]=max([d.datenum]); d=d(ix);
    p=fullfile(d.folder,d.name);
end


function k=subjectKey(ids)
    ids=string(ids);
    k=strings(size(ids));
    for jj=1:numel(ids)
        tok=regexp(char(ids(jj)),'^S\d+','match','once');
        if isempty(tok)
            error('Could not extract numeric subject key from ID: %s',ids(jj));
        end
        k(jj)=string(tok);
    end
end
