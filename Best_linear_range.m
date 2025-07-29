clear; close all; clc;

% -------------------------------
% USER SETTINGS
% -------------------------------
minPoints = 4;  % Minimum number of points per linear fit

% -------------------------------
% Select FIGURE file
% -------------------------------
[figFile, figPath] = uigetfile('*.fig', 'Select compression vs. thickness .fig to analyze and overwrite');
if isequal(figFile, 0)
    disp('User canceled.');
    return;
end

fullFigPath = fullfile(figPath, figFile);

% -------------------------------
% Open figure visibly
% -------------------------------
fig = openfig(fullFigPath, 'visible');
ax = findobj(fig, 'Type', 'axes');
lineObj = findobj(ax, 'Type', 'line');

if isempty(lineObj)
    error('No line plot found in the figure.');
end

x = lineObj.XData(:)';
y = lineObj.YData(:)';
N = numel(x);

% -------------------------------
% Find all valid linear fits
% -------------------------------
fits = [];
for i = 1:N - minPoints + 1
    for j = i + minPoints - 1:N
        xRange = x(i:j);
        yRange = y(i:j);

        p = polyfit(xRange, yRange, 1);
        yFit = polyval(p, xRange);
        SSres = sum((yRange - yFit).^2);
        SStot = sum((yRange - mean(yRange)).^2);
        R2 = 1 - SSres/SStot;

        fits(end+1).range = [i j];
        fits(end).slope = p(1);
        fits(end).intercept = p(2);
        fits(end).R2 = R2;
    end
end

% -------------------------------
% Sort and keep top 3
% -------------------------------
if isempty(fits)
    error('No valid linear ranges found.');
end

[~, sortIdx] = sort([fits.R2], 'descend');
topFits = fits(sortIdx(1:min(3, numel(fits))));

% -------------------------------
% Overlay fits and annotate
% -------------------------------
hold(ax, 'on');
customColors = [ ...
    1.0 0.41 0.71;            % pink
    0.4660 0.6740 0.1880;     % green
    0.3010 0.7450 0.9330];    % teal

% Build title string
titleParts = strings(1, numel(topFits));

for k = 1:numel(topFits)
    idx = topFits(k).range(1):topFits(k).range(2);
    xFit = x(idx);
    yFit = polyval([topFits(k).slope, topFits(k).intercept], xFit);
    plot(ax, xFit, yFit, '-', 'LineWidth', 2, 'Color', customColors(k,:));

    % Label string
    xStart = xFit(1);
    xEnd = xFit(end);
    r2 = topFits(k).R2;
    labelText = sprintf('%d–%d µm: y = %.4fx + %.2f, R² = %.4f', ...
        xStart, xEnd, topFits(k).slope, topFits(k).intercept, r2);
    disp(labelText);

    % Add label to plot
    text(ax, xFit(1), yFit(1), labelText, ...
        'Color', customColors(k,:), 'FontSize', 9, ...
        'FontWeight', 'bold', 'Interpreter', 'none');

    % Save summary for title
    titleParts(k) = sprintf('%d–%d µm (R²=%.4f)', xStart, xEnd, r2);
end

% Update title
title(ax, sprintf('Top 3 Fits: %s', strjoin(titleParts, ', ')));

legend(ax, 'Data', 'Fit 1', 'Fit 2', 'Fit 3', 'Location', 'best');
grid(ax, 'on');

% -------------------------------
% Save over original file
% -------------------------------
savefig(fig, fullFigPath);
fprintf('\nFigure updated and overwritten at:\n%s\n', fullFigPath);

