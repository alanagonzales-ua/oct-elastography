clear; close all; clc;

% -------------------------------
% Select FIG files in order of compression
% -------------------------------
[files, path] = uigetfile('*.fig', ...
    'Select thickness map FIG files in compression order (0 → 100 → ...)', ...
    'MultiSelect', 'on');

if isequal(files, 0)
    disp('No files selected.');
    return;
end

if ischar(files)
    files = {files}; % Convert to cell array if single file selected
end

nFiles = numel(files);

% -------------------------------
% Auto-generate compression levels, adjust for different displacements
% -------------------------------
compressionLevels = (0:200:(nFiles - 1) * 200);

% -------------------------------
% Compute average thickness
% -------------------------------
avgThickness = zeros(1, nFiles);

for i = 1:nFiles
    figPath = fullfile(path, files{i});
    fig = openfig(figPath, 'invisible');
    
    ax = findobj(fig, 'Type', 'axes');
    img = findobj(ax, 'Type', 'image');
    
    if isempty(img)
        error('No image found in: %s', files{i});
    end
    
    data = img.CData;
    close(fig);
    
    % Compute mean ignoring NaNs
    avgThickness(i) = mean(data(~isnan(data)), 'all');
end

% -------------------------------
% Plot
% -------------------------------
figure;
plot(compressionLevels, avgThickness, '-o', 'LineWidth', 2);
xlabel('Compression Level (µm)');
ylabel('Average Thickness (pixels)');
title('Average Phantom Thickness vs. Compression');
grid on;

