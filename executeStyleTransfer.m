function [outputImage] = executeStyleTransfer(unscaledX, unscaledC, unscaledS, isMakingH, unscaledHallIm, unscaledW, L, patch_w, patch_stride)
% unscaledX - estimate so far
% unscaledC - content image
% unscaledS - style image
% isMakingH - true the function is currently being used to generated a
%             hallucinated image
% hallucinatedIm - hallucinated image (representation of pure style)
% unscaledW - weight mask (marks important components of the content image)
% L - working scale
% patch_w - width of square patch
% patch_stride - stride of patch for patch matching

[og_im_h,og_im_w,~] = size(unscaledX);

%% Reshaping based on the selected scaling
C = imresize(unscaledC, 1/L);
S = imresize(unscaledS, 1/L);
W = imresize(unscaledW, 1/L);
X = imresize(unscaledX, 1/L);
hallucinatedIm = imresize(unscaledHallIm,1/L);

im_h = ceil(og_im_h/L); 
im_w = ceil(og_im_w/L);

X = noisyColorTransfer(X,S,5);

%% Style Fusion
% averaged with the hallucinated once we have one
% (won't always because this is used to FIND the hallucinated image)
if ~isMakingH 
    X = (.75*X) + (.25*hallucinatedIm); 
end


%% Patch Matching
% number of patches that actually fit given our patch width and stride
patchFitH = ceil((im_h-patch_w)/patch_stride);
patchFitW = ceil((im_w-patch_w)/patch_stride);

% in order to prevent weird stuff from happening around the outer edges,
% we will add an additional section of patches around the outer edges
numPatchesH = patchFitH + 1; 
numPatchesW = patchFitW + 1;
allPatchLocs = zeros(4, numPatchesH*numPatchesW); % store [xmin, xmax, ymin, ymax] (patchH = i, patchW = j)
matchingPatches = zeros(4,numPatchesH*numPatchesW);

% note that i and j are the PATCH indices (not in pixels)
patchIndex = 1;
for i=1:numPatchesH
    ipix = (i-1)*patch_stride + 1;
    
    % if we are at the edge, shift patch in so we don't overhang
    if i==numPatchesH
        iLow = im_h-patch_w+1;
        iHigh = im_h;
    else
        iLow = ipix;
        iHigh = ipix+patch_w-1;
    end
    
    for j=1:numPatchesW
        jpix = (j-1)*patch_stride + 1;
        
        % if we are at the edge, shift patch in so we don't overhang
        if j==numPatchesW
            jLow = im_w-patch_w+1;
            jHigh = im_w;
        else
            jLow = jpix;
            jHigh = jpix+patch_w-1;
        end
        
        allPatchLocs(:, patchIndex) = [iLow, iHigh, jLow, jHigh];        
        matchingPatches(:, patchIndex) = getPatchMatch(X, S, patch_w, patch_stride, iLow, iHigh, jLow, jHigh);
        
%         allPatchLocs(:,(i-1)*numPatchesW+j) = patchLocCol; % get to the correct spot in this flattened matrix
%         
%         matchingPatch = getPatchMatch(X, S, patch_w, patch_stride, iLow, iHigh, jLow, jHigh);
%         matchingPatches(:,(i-1)*numPatchesW+j) = reshape(matchingPatch,[patch_w*patch_w*3,1]);
%         matchingPatches(:,(i-1)*numPatchesW+j) = reshape(matchingPatch,[patch_w*patch_w*3,1]);
        patchIndex = patchIndex + 1;

    end
end

%% Style Synthesis
% use IRLS to find styledX such that we minimize the distance between
% each patch in styledX with its best matching patch (see matchingPatches)
% Algorithm modeled after Iterative Reweighted Least Squares, Sidney Burrus
styledX = X(:);
p = .8;
num_IRLS_iters = 5;
% [~,totalPatches] = size(allPatchLocs);
totalPatches = patchIndex - 1;
for k=1:num_IRLS_iters
    A = zeros(size(styledX));
    B = zeros(size(styledX));
    for t=1:totalPatches
        patch = zeros(im_h, im_w, 3);
        iLow = allPatchLocs(1, t); 
        iHigh = allPatchLocs(2, t); 
        jLow = allPatchLocs(3, t);  
        jHigh = allPatchLocs(4, t);
        patch(iLow:iHigh, jLow:jHigh, :) = 1;
        
        reshaped_patch = patch(:);
        selectThisPatch = logical(reshaped_patch);
        
        xLow = matchingPatches(1, t);
        xHigh = matchingPatches(2, t);
        yLow = matchingPatches(3, t);
        yHigh = matchingPatches(4, t);
        matchingPatch = reshape(S(xLow: xHigh, yLow: yHigh, :), [patch_w*patch_w*3,1]);
        w=sum((styledX(selectThisPatch)-matchingPatch).^2).^((p-2)/2);
        A=A+w*reshaped_patch;
        
        useThisMatch = reshaped_patch;
        useThisMatch(selectThisPatch) = matchingPatch;
        B=B+w*useThisMatch;
    end
    styledX=(1./A).*B;
end


%% Content Fusion
if isMakingH
    weightweight = 0;
else
    weightweight = 3;
end

coloredC = imhistmatch(C,S);
Wnorm = max(W(:));
flatW = repmat(W(:)/Wnorm,3,1)*weightweight;
contentFusedX = (1./(flatW + ones(size(flatW)))).*(styledX + flatW.*double(coloredC(:)));

%% Color Transfer
coloredX = imhistmatch(reshape(contentFusedX,[im_h,im_w,3]), S);

%% Denoise?

%% Scale image back up to original dimensions 
scaledUpX = imresize(coloredX,L);
outputImage = scaledUpX;
end

