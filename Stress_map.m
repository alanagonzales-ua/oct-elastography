clear; close all; clc;

% =============================
% User Options
% =============================
removeOutliers = false;
lowerThresh = 0.1;
upperThresh = 10.0;

cLim = [0, 2500];          

applyMultiplier = true;   
multiplierConst = 49377; 

% =============================
% File Selection
% =============================
[refFile, refPath] = uigetfile('*.fig', 'Select the REFERENCE thickness map');
if isequal(refFile, 0), disp('Cancelled.'); return; end

[defFile, defPath] = uigetfile('*.fig', 'Select the DEFORMED thickness map');
if isequal(defFile, 0), disp('Cancelled.'); return; end

% =============================
% Load Thickness Maps
% =============================
refFig = openfig(fullfile(refPath, refFile), 'invisible');
refAx  = findobj(refFig, 'Type', 'axes');
refImg = findobj(refAx, 'Type', 'image');
thicknessRef = refImg.CData;
close(refFig);

defFig = openfig(fullfile(defPath, defFile), 'invisible');
defAx  = findobj(defFig, 'Type', 'axes');
defImg = findobj(defAx, 'Type', 'image');
thicknessDef = defImg.CData;
close(defFig);

% =============================
% Ask for Division Factor
% =============================
prompt = {'Enter division factor for strain values:'};
dlgtitle = 'Strain Scaling';
dims = [1 50];
definput = {'1'};
answer = inputdlg(prompt, dlgtitle, dims, definput);

if isempty(answer)
    disp('User canceled division factor input.');
    return;
end

scaleFactor = str2double(answer{1});
if isnan(scaleFactor) || scaleFactor == 0
    errordlg('Invalid scale factor. Must be a non-zero number.', 'Input Error');
    return;
end

% =============================
% Compute Strain Map
% =============================
strainMap = ((thicknessRef - thicknessDef) ./ thicknessRef) / scaleFactor;

% Apply constant multiplier (e.g., convert to new units)
if applyMultiplier
    strainMap = strainMap * multiplierConst;
end

% =============================
% Optional Outlier Removal
% =============================
if removeOutliers
    strainMedian = median(strainMap(~isnan(strainMap)), 'all');
    outlierMask = strainMap < lowerThresh * strainMedian | strainMap > upperThresh * strainMedian;
    strainMap(outlierMask) = NaN;
end

% =============================
% Compute Average Strain
% =============================
avgStrain = mean(strainMap(~isnan(strainMap)), 'all');

% =============================
% Load Colormap
% =============================
data = load('turbo_colormap_1024.mat');
% data = load('viridis_yellow_to_purple.mat');

% =============================
% Display Map
% =============================
fig = figure;
hImg = imagesc(strainMap);
axis image off;
colormap(data.turboRGB);
colorbar;
caxis(cLim);
set(hImg, 'AlphaData', ~isnan(strainMap));

titleStr = sprintf(['Strain Map: %s - %s', ...
    '\nAverage Value: %.4f', ...
    '\nDivision Factor: %.2f, Multiplier: %.2f'], ...
    strrep(refFile, '_', ' '), strrep(defFile, '_', ' '), ...
    avgStrain, scaleFactor, multiplierConst);
title(titleStr, 'Interpreter', 'none');

% =============================
% Save File
% =============================
savePath = refPath;
[~, refNameOnly, ~] = fileparts(refFile);
refBase = regexprep(refNameOnly, '[_ ]thickness$', '', 'ignorecase');
defaultBaseName = [refBase, '_strain'];

filenamePrompt = {'Enter base filename (no extension):'};
filenameTitle = 'Save Filename';
filenameInput = inputdlg(filenamePrompt, filenameTitle, [1 50], {defaultBaseName});
if isempty(filenameInput)
    disp('Filename input canceled.');
    return;
end
baseName = filenameInput{1};

savefig(fig, fullfile(savePath, [baseName, '.fig']));
disp(['Figure saved as: ', fullfile(savePath, [baseName, '.fig'])]);

% =============================
% Save PNG with Alpha
% =============================
strainMapNorm = (strainMap - cLim(1)) / (cLim(2) - cLim(1));
strainMapNorm = min(max(strainMapNorm, 0), 1);

strainRGB = ind2rgb(round(strainMapNorm * (size(data.turboRGB,1)-1)) + 1, data.turboRGB);
alphaChannel = uint8(255 * ~isnan(strainMap));

imwrite(strainRGB, fullfile(savePath, [baseName, '.png']), 'Alpha', alphaChannel);
disp(['PNG saved as: ', fullfile(savePath, [baseName, '.png'])]);
