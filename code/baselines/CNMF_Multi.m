function [U_final, Z_final, nIter_final, objhistory_final] = CNMF_Multi(X,A,k,W,options,U,Z)
% Graph regularized Non-negative Matrix Factorization (GNMF) with
%          multiplicative update  2012��Haifeng Liu 2014.12.1
%
% where
%   X
% Notation:
% X ... (mFea x nSmp) data matrix 
%       mFea  ... number of words (vocabulary size)
%       nSmp  ... number of documents
% A     label constraint matrix  
% k ... number of hidden factors
% W ... weight matrix of the affinity graph 
%
% options ... Structure holding all settings
%
% You only need to provide the above four inputs.
%
% X = U*V'
%
% References:
% [1] Deng Cai, Xiaofei He, Xiaoyun Wu, and Jiawei Han. "Non-negative
% Matrix Factorization on Manifold", Proc. 2008 Int. Conf. on Data Mining
% (ICDM'08), Pisa, Italy, Dec. 2008. 
%
% [2] Deng Cai, Xiaofei He, Jiawei Han, Thomas Huang. "Graph Regularized
% Non-negative Matrix Factorization for Data Representation", IEEE
% Transactions on Pattern Analysis and Machine Intelligence, , Vol. 33, No.
% 8, pp. 1548-1560, 2011.  
%
%
%   version 2.1 --Dec./2011 
%   version 2.0 --April/2009 
%   version 1.0 --April/2008 
%
%   Written by Deng Cai (dengcai AT gmail.com)
%

differror = options.error;
maxIter = options.maxIter;
nRepeat = options.nRepeat;
minIter = options.minIter - 1;
if ~isempty(maxIter) && maxIter < minIter
    minIter = maxIter;
end
meanFitRatio = options.meanFitRatio;

alpha = options.alpha;

Norm = 2;
NormV = 0;

[mFea,nSmp]=size(X);

if alpha > 0
    W = alpha*W;             
    DCol = full(sum(W,2));   

    D = spdiags(DCol,0,nSmp,nSmp); 
    L = D - W;                  % graph Laplacian
    if isfield(options,'NormW') && options.NormW
        D_mhalf = spdiags(DCol.^-.5,0,nSmp,nSmp) ;
        L = D_mhalf*L*D_mhalf;
    end
else
    L = [];
end

selectInit = 1;
if isempty(U)
      U = abs(rand(mFea,k));   
      Z = abs(rand(size(A,2),k));
else
      nRepeat = 1;
end
    
[U,Z] = NormalizeUV(U,Z, NormV, Norm);
 
if nRepeat == 1
    selectInit = 0;
    minIter = 0;
    if isempty(maxIter)
        objhistory = CalculateObj(X, U, A*Z, L);
        meanFit = objhistory*10;
    else
        if isfield(options,'Converge') && options.Converge
            objhistory = CalculateObj(X, U, A*Z, L);
        end
    end
else
    if isfield(options,'Converge') && options.Converge
        error('Not implemented!');
    end
end


tryNo = 0;
nIter = 0;
while tryNo < nRepeat   
    tryNo = tryNo+1;
    maxErr = 1;
    while(maxErr > differror)
        % ===================== update Z ========================
        AXU=A'*X'*U;
        AAZ=A'*A*Z*U'*U;
     
        if alpha > 0
            ZW = A'*W*A*Z;
            ZD = A'*D*A*Z;
            
            AXU = AXU + ZW;
            AAZ = AAZ + ZD;
        end
        
        Z = Z.*(AXU./max(AAZ,1e-10));
        
        % ===================== update U ========================
        XAZ=X*A*Z;
        UZA=U*Z'*A'*A*Z;
       
         U = U.*(XAZ./max(UZA,1e-10));
        nIter = nIter + 1;
        if nIter > minIter
            if selectInit
                objhistory = CalculateObj(X, U, A*Z, L);
                maxErr = 0;
            else
                if isempty(maxIter)
                    newobj = CalculateObj(X, U, A*Z, L);
                    objhistory = [objhistory newobj];
                    meanFit = meanFitRatio*meanFit + (1-meanFitRatio)*newobj;
                    maxErr = (meanFit-newobj)/meanFit;
                else
                    if isfield(options,'Converge') && options.Converge
                        newobj = CalculateObj(X, U, A*Z, L);
                        objhistory = [objhistory newobj];
                    end
                    maxErr = 1;
                    if nIter >= maxIter
                        maxErr = 0;
                        if isfield(options,'Converge') && options.Converge
                        else
                            objhistory = 0;
                        end
                    end
                end
            end

        end

    end
    
    if tryNo == 1
        U_final = U;
        Z_final = Z;
        nIter_final = nIter;
        objhistory_final = objhistory;
    else
       if objhistory(end) < objhistory_final(end)
           U_final = U;
           Z_final = Z;
           nIter_final = nIter;
           objhistory_final = objhistory;
       end
    end

    if selectInit   
        if tryNo < nRepeat

            U = abs(rand(mFea,k));
            Z = abs(rand(size(A,2),k));
            
            [U,Z] = NormalizeUV(U, Z, NormV, Norm);
            nIter = 0;
        else
            tryNo = tryNo - 1;
            nIter = minIter+1;
            selectInit = 0;
            U = U_final;
            Z = Z_final;
            objhistory = objhistory_final;
            meanFit = objhistory*10;
        end
    end
end

[U_final,Z_final] = NormalizeUV(U_final, Z_final, NormV, Norm);


%==========================================================================

function [obj, dV] = CalculateObj(X, U, V, L, deltaVU, dVordU)
    MAXARRAY = 500*1024*1024/8;            % 500M. You can modify this number based on your machine's computational power.
    if ~exist('deltaVU','var')
        deltaVU = 0;
    end
    if ~exist('dVordU','var')
        dVordU = 1;
    end
    dV = [];
    nSmp = size(X,2);
    mn = numel(X);
    nBlock = ceil(mn/MAXARRAY);

    if mn < MAXARRAY
        dX = U*V'-X;
        obj_NMF = sum(sum(dX.^2));
        if deltaVU
            if dVordU
                dV = dX'*U + L*V;
            else
                dV = dX*V;
            end
        end
    else
        obj_NMF = 0;
        if deltaVU
            if dVordU
                dV = zeros(size(V));
            else
                dV = zeros(size(U));
            end
        end
        PatchSize = ceil(nSmp/nBlock);
        for i = 1:nBlock
            if i*PatchSize > nSmp
                smpIdx = (i-1)*PatchSize+1:nSmp;
            else
                smpIdx = (i-1)*PatchSize+1:i*PatchSize;
            end
            dX = U*V(smpIdx,:)'-X(:,smpIdx);
            obj_NMF = obj_NMF + sum(sum(dX.^2));
            if deltaVU
                if dVordU
                    dV(smpIdx,:) = dX'*U;
                else
                    dV = dU+dX*V(smpIdx,:);
                end
            end
        end
        if deltaVU
            if dVordU
                dV = dV + L*V;
            end
        end
    end
    if isempty(L)
        obj_Lap = 0;
    else
        obj_Lap = sum(sum((V'*L).*V'));
    end
    obj = obj_NMF+obj_Lap;
    




function [U, V] = NormalizeUV(U, V, NormV, Norm)
    K = size(U,2);
    if Norm == 2
        if NormV
            norms = max(1e-15,sqrt(sum(V.^2,1)))';
            V = V*spdiags(norms.^-1,0,K,K);           
            U = U*spdiags(norms,0,K,K);
        else
            norms = max(1e-15,sqrt(sum(U.^2,1)))';
            U = U*spdiags(norms.^-1,0,K,K);
            V = V*spdiags(norms,0,K,K);
        end
    else
        if NormV
            norms = max(1e-15,sum(abs(V),1))';
            V = V*spdiags(norms.^-1,0,K,K);
            U = U*spdiags(norms,0,K,K);
        else
            norms = max(1e-15,sum(abs(U),1))';
            U = U*spdiags(norms.^-1,0,K,K);
            V = V*spdiags(norms,0,K,K);
        end
    end

        