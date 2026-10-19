%% stage1_realfit_JND_vs_Free_v1.m
% Stage 1: refit REAL motion data with Free and JND-informed model families
% under identical Monte-Carlo draws and optimization settings.

ANALYSIS_ROOT='C:\MSI\oscillation\ternus AV BCI\analysis0906';
SCRIPT_DIR=fullfile(ANALYSIS_ROOT,'analysis');
PHASE2_DIR=fullfile(ANALYSIS_ROOT,'Analysis_Output_v4_R2_070');
PHASE2_MAT=fullfile(PHASE2_DIR,'Phase2_Analysis_Results_v4.mat');
OUT_DIR=fullfile(PHASE2_DIR,'Overnight_JND_BCI_v1');
if ~exist(OUT_DIR,'dir'),mkdir(OUT_DIR);end
addpath(SCRIPT_DIR);

MODEL_CODES=[1 4 5];
MODEL_NAMES={'ModelAveraging','ForcedFusion','Segregation'};
FAMILIES={'Free','JNDInformed'};
FREE_K=[6 5 5]; JND_K=[5 4 4];

N_SIM_REAL=6000;
N_STARTS_FINAL=20;
N_STARTS_CHECK=5;
opts=optimset('MaxIter',1400,'MaxFunEvals',7000,'Display','off','TolFun',1e-4,'TolX',1e-4);

S=load(PHASE2_MAT,'qualityTable','trialTable');
q=S.qualityTable; T=S.trialTable;
ids=string(q.ID(q.R2PrimaryIncluded));

fprintf('Stage1: N=%d | N_SIM=%d | starts=%d (stability check vs %d starts)\n', ...
    numel(ids),N_SIM_REAL,N_STARTS_FINAL,N_STARTS_CHECK);

tasks=["AttendV","AttendA"];
modelTasks=["Attend_V","Attend_A"];
nTotal=numel(ids)*numel(tasks)*numel(FAMILIES)*numel(MODEL_CODES);
done=0; t0=tic;
rows=cell(0,25);

for it=1:numel(tasks)
    for is=1:numel(ids)
        sid=ids(is);
        [info,jA,jV]=prepareConditionData(T,q,sid,tasks(it));
        if isempty(info.counts),continue;end

        seed=73000000+it*100000+is*1000;
        old=rng;rng(seed,'twister');
        xA=randn(info.nCond,N_SIM_REAL);
        xV=randn(info.nCond,N_SIM_REAL);
        rng(old);

        for iff=1:numel(FAMILIES)
            fam=string(FAMILIES{iff});
            for im=1:numel(MODEL_CODES)
                code=MODEL_CODES(im);
                mname=string(MODEL_NAMES{im});
                fitSeed=seed+iff*100+im*10;

                if fam=="Free"
                    [phi5,k5,nll5]=fitFree(info,info.counts,char(modelTasks(it)),code, ...
                        jA,jV,xA,xV,N_STARTS_CHECK,fitSeed,opts);
                    [phi,kHat,nll]=fitFree(info,info.counts,char(modelTasks(it)),code, ...
                        jA,jV,xA,xV,N_STARTS_FINAL,fitSeed,opts);
                    K=FREE_K(im);
                else
                    kStart=2;
                    [phi5,k5,nll5]=fitJND(info,info.counts,char(modelTasks(it)),code, ...
                        jA,jV,xA,xV,N_STARTS_CHECK,fitSeed,opts,kStart);
                    [phi,kHat,nll]=fitJND(info,info.counts,char(modelTasks(it)),code, ...
                        jA,jV,xA,xV,N_STARTS_FINAL,fitSeed,opts,kStart);
                    K=JND_K(im);
                end

                nTrials=sum(info.counts(:));
                LL=-nll; AIC=2*nll+2*K; BIC=2*nll+K*log(nTrials);
                improvement=nll5-nll;

                rows(end+1,:)={char(sid),char(tasks(it)),char(fam),char(mname), ...
                    nTrials,jA,jV,kHat,phi(1),phi(2),phi(3),phi(4),phi(5),phi(6), ...
                    LL,AIC,BIC,K,nll,nll5,improvement,N_SIM_REAL,N_STARTS_FINAL,fitSeed,code}; %#ok<AGROW>

                done=done+1;
                elapsed=toc(t0); eta=elapsed/max(done,1)*(nTotal-done);
                fprintf('Stage1 %4d/%4d (%5.1f%%) | %s %s | %-11s %-14s | elapsed %s | ETA %s\n', ...
                    done,nTotal,100*done/nTotal,char(sid),char(tasks(it)),char(fam),char(mname), ...
                    fmtTime(elapsed),fmtTime(eta));
            end
        end
    end
end

fits=cell2table(rows,'VariableNames',{'Subject','Task','FitFamily','Model','NTrials', ...
    'JND_A','JND_V','Fit_k','pCommon','muP','sigP','sigA','sigV','Criterion', ...
    'LLK','AIC','BIC','K','NegLL','NegLL_5starts','Improvement_20minus5', ...
    'NSim','NStarts','Seed','ModelCode'});
writetable(fits,fullfile(OUT_DIR,'RealData_AllFits.csv'));

% Individual winners within each family and across all six conditional candidates.
wrows=cell(0,8);
for it=1:numel(tasks)
    for is=1:numel(ids)
        sid=ids(is);
        for iff=1:numel(FAMILIES)
            fam=string(FAMILIES{iff});
            x=fits(string(fits.Subject)==sid&string(fits.Task)==tasks(it)&string(fits.FitFamily)==fam,:);
            if height(x)~=3,continue;end
            [bs,ord]=sort(x.BIC,'ascend');
            wrows(end+1,:)={char(sid),char(tasks(it)),char(fam),char(string(x.Model(ord(1)))), ...
                bs(1),bs(2)-bs(1),char(fam),double(fam=="JNDInformed")}; %#ok<AGROW>
        end
        x=fits(string(fits.Subject)==sid&string(fits.Task)==tasks(it),:);
        if height(x)==6
            [bs,ord]=sort(x.BIC,'ascend');
            label=string(x.FitFamily(ord(1)))+":"+string(x.Model(ord(1)));
            wrows(end+1,:)={char(sid),char(tasks(it)),'AllSixConditional',char(label), ...
                bs(1),bs(2)-bs(1),char(string(x.FitFamily(ord(1)))), ...
                double(string(x.FitFamily(ord(1)))=="JNDInformed")}; %#ok<AGROW>
        end
    end
end
winners=cell2table(wrows,'VariableNames',{'Subject','Task','ComparisonSet','Winner', ...
    'BestBIC','DeltaBIC_SecondMinusBest','WinningFamily','WinnerIsJNDInformed'});
writetable(winners,fullfile(OUT_DIR,'RealData_IndividualWinners.csv'));

% Group evidence.
grows=cell(0,12);
for it=1:numel(tasks)
    for iff=1:numel(FAMILIES)
        fam=string(FAMILIES{iff});
        sums=nan(1,3); nwin=zeros(1,3);
        for im=1:3
            x=fits(string(fits.Task)==tasks(it)&string(fits.FitFamily)==fam& ...
                string(fits.Model)==string(MODEL_NAMES{im}),:);
            sums(im)=sum(x.BIC,'omitnan');
        end
        z=fits(string(fits.Task)==tasks(it)&string(fits.FitFamily)==fam,:);
        subs=unique(string(z.Subject));
        for is=1:numel(subs)
            u=z(string(z.Subject)==subs(is),:);
            [~,ix]=min(u.BIC);
            jj=find(string(MODEL_NAMES)==string(u.Model(ix)),1);
            nwin(jj)=nwin(jj)+1;
        end
        ww=bicWeightsLocal(sums);
        [~,ord]=sort(sums,'ascend');
        grows(end+1,:)={char(tasks(it)),char(fam),sums(1),sums(2),sums(3), ...
            ww(1),ww(2),ww(3),MODEL_NAMES{ord(1)},nwin(1),nwin(2),nwin(3)}; %#ok<AGROW>
    end
end
group=cell2table(grows,'VariableNames',{'Task','FitFamily','SumBIC_MA','SumBIC_FF','SumBIC_Seg', ...
    'Weight_MA','Weight_FF','Weight_Seg','GroupWinner','NWin_MA','NWin_FF','NWin_Seg'});
writetable(group,fullfile(OUT_DIR,'RealData_GroupEvidence.csv'));

% All-six conditional group comparison (conditional on estimated baseline JND).
srows=cell(0,7);
for it=1:numel(tasks)
    labels=strings(6,1); sums=nan(6,1); kk=0;
    for iff=1:numel(FAMILIES)
        for im=1:3
            kk=kk+1;
            fam=string(FAMILIES{iff}); m=string(MODEL_NAMES{im});
            labels(kk)=fam+":"+m;
            x=fits(string(fits.Task)==tasks(it)&string(fits.FitFamily)==fam&string(fits.Model)==m,:);
            sums(kk)=sum(x.BIC,'omitnan');
        end
    end
    ww=bicWeightsLocal(sums');
    best=min(sums);
    for k=1:6
        srows(end+1,:)={char(tasks(it)),char(labels(k)),sums(k),sums(k)-best,ww(k), ...
            double(startsWith(labels(k),"JNDInformed:")),double(sums(k)==best)}; %#ok<AGROW>
    end
end
allSix=cell2table(srows,'VariableNames',{'Task','Candidate','SumBIC','DeltaBIC_FromBest', ...
    'ConditionalBICWeight','IsJNDInformed','IsGroupWinner'});
writetable(allSix,fullfile(OUT_DIR,'RealData_AllSixConditionalEvidence.csv'));

% Optimization stability.
orows=cell(0,9);
for it=1:numel(tasks)
    for iff=1:numel(FAMILIES)
        for im=1:3
            x=fits(string(fits.Task)==tasks(it)&string(fits.FitFamily)==string(FAMILIES{iff})& ...
                string(fits.Model)==string(MODEL_NAMES{im}),:);
            d=x.Improvement_20minus5;
            orows(end+1,:)={char(tasks(it)),FAMILIES{iff},MODEL_NAMES{im},height(x), ...
                mean(d,'omitnan'),median(d,'omitnan'),sum(d>0.1),sum(d>1),max(d)}; %#ok<AGROW>
        end
    end
end
optstab=cell2table(orows,'VariableNames',{'Task','FitFamily','Model','N', ...
    'MeanNLLImprovement','MedianNLLImprovement','NImproved_gt0p1','NImproved_gt1','MaxImprovement'});
writetable(optstab,fullfile(OUT_DIR,'RealData_OptimizationStability.csv'));

fprintf('\nSTAGE1 REAL-DATA GROUP EVIDENCE\n'); disp(group);
fprintf('\nSTAGE1 ALL-SIX CONDITIONAL EVIDENCE\n'); disp(allSix);
fprintf('\nSTAGE1 OPTIMIZATION STABILITY\n'); disp(optstab);
save(fullfile(OUT_DIR,'Stage1_RealData.mat'),'fits','winners','group','allSix','optstab','-v7.3');

function w=bicWeightsLocal(b)
b=double(b(:)');
z=exp(-0.5*(b-min(b)));
w=z/sum(z);
end


function [info,jA,jV]=prepareConditionData(T,q,sid,task)
    qi=find(string(q.ID)==sid,1);
    if isempty(qi),error('Missing q row for %s',sid);end
    jA=q.A_JND(qi);jV=q.V_JND(qi);

    d=T(string(T.Subject)==sid & string(T.Task)==task,:);
    d=d(isfinite(d.RespMotion)&isfinite(d.CenteredA)&isfinite(d.CenteredV)& ...
        isfinite(d.ISI_A)&isfinite(d.ISI_V),:);

    if isempty(d)
        info=struct('counts',[],'sA',[],'sV',[],'nCond',0);
        return;
    end

    nominal=[d.ISI_A,d.ISI_V];
    [~,~,g]=unique(nominal,'rows');
    nCond=max(g);
    counts=zeros(nCond,2);
    sA=zeros(nCond,1);sV=zeros(nCond,1);

    for c=1:nCond
        idx=g==c;
        counts(c,:)=[sum(d.RespMotion(idx)==0),sum(d.RespMotion(idx)==1)];
        sA(c)=mean(d.CenteredA(idx),'omitnan');
        sV(c)=mean(d.CenteredV(idx),'omitnan');
    end

    info=struct('counts',counts,'sA',sA,'sV',sV,'nCond',nCond);
end

function [phiHat,kHat,bestNLL]=fitFree(info,counts,modelTask,modelCode,jA,jV,xA,xV,nStarts,seed,opts)
    LB=[0.001,-180,1,1,1,-180];
    UB=[0.999, 180,250,250,250,180];
    start=[0.5,0,60,30,30,0];

    freeMask=true(1,6);
    fixed=nan(1,6);
    if modelCode==4
        freeMask(1)=false;fixed(1)=1;
    elseif modelCode==5
        freeMask(1)=false;fixed(1)=0;
    end

    param=struct('iModel',modelCode,'taskName',modelTask, ...
        'sA',repmat(info.sA,1,size(xA,2)),'sV',repmat(info.sV,1,size(xV,2)), ...
        'xAPre',xA,'xVPre',xV,'dataCounts',counts,'freeMask',freeMask,'fixedPhi',fixed);

    bestNLL=inf;phiHat=nan(1,6);
    old=rng;rng(seed,'twister');

    for st=1:nStarts
        if st==1
            x0=start;
        else
            x0=LB+rand(1,6).*(UB-LB);
        end
        if modelCode~=1,x0(1)=fixed(1);end

        [xh,nll]=boundedFminsearch(@(z) negLLFree(z,param), ...
            x0(freeMask),LB(freeMask),UB(freeMask),opts);

        if isfinite(nll)&&nll<bestNLL
            bestNLL=nll;
            tmp=fixed;tmp(freeMask)=xh;phiHat=tmp;
        end
    end
    rng(old);

    % Implied scale is descriptive only for the unconstrained family.
    if all(isfinite(phiHat([4 5])))
        kHat=sqrt((phiHat(4)/jA)*(phiHat(5)/jV));
    else
        kHat=NaN;
    end
end

function nll=negLLFree(z,param)
    try
        phi=param.fixedPhi;
        phi(param.freeMask)=z;
        [p,~]=computeRespDistrib_AVTernus_v4(phi,param);
        nll=binomialNLL(param.dataCounts,p(:,2));
    catch
        nll=1e12;
    end
end

function [phiHat,kHat,bestNLL]=fitJND(info,counts,modelTask,modelCode,jA,jV,xA,xV,nStarts,seed,opts,kStart)
    [kLB,kUB]=kBounds(jA,jV);

    if modelCode==1
        LB=[0.001,-180,1,kLB,-180];
        UB=[0.999, 180,250,kUB, 180];
        start=[0.5,0,60,min(max(kStart,kLB),kUB),0];
    else
        LB=[-180,1,kLB,-180];
        UB=[ 180,250,kUB,180];
        start=[0,60,min(max(kStart,kLB),kUB),0];
    end

    param=struct('iModel',modelCode,'taskName',modelTask, ...
        'sA',repmat(info.sA,1,size(xA,2)),'sV',repmat(info.sV,1,size(xV,2)), ...
        'xAPre',xA,'xVPre',xV,'dataCounts',counts,'JND_A',jA,'JND_V',jV);

    bestNLL=inf;phiHat=nan(1,6);kHat=NaN;
    old=rng;rng(seed,'twister');

    for st=1:nStarts
        if st==1
            x0=start;
        else
            x0=LB+rand(1,numel(LB)).*(UB-LB);
        end

        [xh,nll]=boundedFminsearch(@(z) negLLJND(z,param),x0,LB,UB,opts);
        if isfinite(nll)&&nll<bestNLL
            bestNLL=nll;
            [phi,k]=thetaToPhiJND(xh,param);
            phiHat=phi;kHat=k;
        end
    end
    rng(old);
end

function nll=negLLJND(theta,param)
    try
        [phi,~]=thetaToPhiJND(theta,param);
        [p,~]=computeRespDistrib_AVTernus_v4(phi,param);
        nll=binomialNLL(param.dataCounts,p(:,2));
    catch
        nll=1e12;
    end
end

function [phi,k]=thetaToPhiJND(theta,param)
    theta=double(theta(:)');
    if param.iModel==1
        if numel(theta)~=5,error('MA JND theta must have 5 params');end
        pC=theta(1);mu=theta(2);sigP=theta(3);k=theta(4);crit=theta(5);
    else
        if numel(theta)~=4,error('FF/Seg JND theta must have 4 params');end
        mu=theta(1);sigP=theta(2);k=theta(3);crit=theta(4);
        if param.iModel==4,pC=1;else,pC=0;end
    end

    sigA=k*param.JND_A;
    sigV=k*param.JND_V;
    phi=[pC,mu,sigP,sigA,sigV,crit];
end

function nll=binomialNLL(counts,pGroup)
    pGroup=min(max(double(pGroup(:)),realmin('double')),1-realmin('double'));
    counts=double(counts);
    n=sum(counts,2);k0=counts(:,1);k1=counts(:,2);
    ll=gammaln(n+1)-gammaln(k0+1)-gammaln(k1+1)+ ...
       k0.*log(1-pGroup)+k1.*log(pGroup);
    nll=-sum(ll);
    if ~isscalar(nll)||~isfinite(nll),nll=1e12;end
end

function [lb,ub]=kBounds(jA,jV)
    % Preserve the original sensory-sigma bounds [1,250] ms in both modalities.
    lb=max([1/jA,1/jV,1e-4]);
    ub=min([250/jA,250/jV,100]);
    if ~isfinite(lb)||~isfinite(ub)||ub<=lb
        error('Invalid k bounds for JND_A=%.4f JND_V=%.4f',jA,jV);
    end
end

function synth=drawSyntheticCounts(realCounts,pGroup,seed)
    old=rng;rng(seed,'twister');
    synth=zeros(size(realCounts));
    for c=1:size(realCounts,1)
        n=sum(realCounts(c,:));
        pg=min(max(pGroup(c),0),1);
        kg=sum(rand(n,1)<pg);
        synth(c,:)=[n-kg,kg];
    end
    rng(old);
end

function [xBest,fBest]=boundedFminsearch(fun,x0,lb,ub,options)
    x0=double(x0(:)');lb=double(lb(:)');ub=double(ub(:)');
    margin=max(1e-10,1e-8*(ub-lb));
    x0=min(max(x0,lb+margin),ub-margin);
    ratio=(x0-lb)./(ub-x0);
    y0=log(ratio);
    trans=@(y) lb+(ub-lb)./(1+exp(-min(max(y,-50),50)));
    [yb,fBest]=fminsearch(@(y) fun(trans(y)),y0,options);
    xBest=trans(yb);
end


function s=fmtTime(sec)
    if ~isfinite(sec),s='--:--:--';return;end
    sec=round(sec);
    h=floor(sec/3600);
    m=floor(mod(sec,3600)/60);
    ss=mod(sec,60);
    s=sprintf('%02d:%02d:%02d',h,m,ss);
end
