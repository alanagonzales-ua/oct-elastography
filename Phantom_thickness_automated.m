clear; close all; clc;

% Select folder containing TIFF stacks
folderPath = uigetdir(pwd, 'Select folder containing TIFF stacks');
if folderPath == 0
    disp('User canceled file selection.');
    return;
end

% ============================
% User Parameters
% ============================
tolerance = 1;            % Minimum peak prominence
peakRatioThresh = 0.7;   % Second peak must be at least this ratio of first
minSeparation = 30;      % Minimum pixel separation between peaks
maxSeparation = 550;      % Maximum pixel separation between peaks
glassSlideCrop = 150;       % Crop this many pixels from the top of each image before analysis
% ============================

fprintf('Using settings:\n');
fprintf(' - Peak Prominence Tolerance: %.2f\n', tolerance);
fprintf(' - Peak Ratio Threshold: %.2f\n', peakRatioThresh);
fprintf(' - Min Peak Separation: %d px\n', minSeparation);
fprintf(' - Max Peak Separation: %d px\n', maxSeparation);
fprintf(' - Glass Slide Crop: %d px\n\n', glassSlideCrop);

% Get all TIFF files in the folder
fileList = dir(fullfile(folderPath, '*.tif'));
fileList = [fileList; dir(fullfile(folderPath, '*.tiff'))];

if isempty(fileList)
    disp('No TIFF stacks found in the selected folder.');
    return;
end

numFiles = length(fileList);
fprintf('Processing %d TIFF files...\n\n', numFiles);
tic;  % Start timer

for f = 1:numFiles
    filename = fileList(f).name;
    filepath = fullfile(folderPath, filename);
    info = imfinfo(filepath);
    num_slices = numel(info);

    sample_img = imread(filepath, 1);
    if ndims(sample_img) == 3
        sample_img = rgb2gray(sample_img);
    end
    sample_img = double(sample_img);

    if glassSlideCrop > 0
        sample_img = sample_img(glassSlideCrop+1:end, :);
    end
    [height, width] = size(sample_img);

    thickness_map = NaN(num_slices, width);
    image_stack = zeros(height, width, num_slices);

    for j = 1:num_slices
        img = imread(filepath, j);
        if ndims(img) == 3
            img = rgb2gray(img);
        end
        img = double(img);
        if glassSlideCrop > 0
            img = img(glassSlideCrop+1:end, :);
        end
        image_stack(:, :, j) = img;

        for i = 1:width
            profile = img(:, i);
            [vals, locs] = findpeaks(profile, 'MinPeakProminence', tolerance);

            if numel(vals) >= 2
                global_max = max(vals);
                for a = 1:numel(vals)-1
                    if vals(a) >= 0.9 * global_max
                        found = false;
                        for b = a+1:numel(vals)
                            thickness = abs(locs(b) - locs(a));
                            if vals(b) >= peakRatioThresh * vals(a) && ...
                               thickness >= minSeparation && thickness <= maxSeparation
                                thickness_map(j, i) = thickness;
                                found = true;
                                break;
                            end
                        end
                        if ~found
                            for b = a+1:numel(vals)
                                thickness = abs(locs(b) - locs(a));
                                if vals(b) >= peakRatioThresh * vals(a) && ...
                                   thickness >= minSeparation && thickness <= maxSeparation
                                    thickness_map(j, i) = thickness;
                                    break;
                                end
                            end
                        end
                        break;
                    end
                end
            end
        end
    end

    % Remove obvious outliers and isolated values
    for row = 1:size(thickness_map, 1)
        for col = 2:size(thickness_map, 2)-1
            curr = thickness_map(row, col);
            left = thickness_map(row, col-1);
            right = thickness_map(row, col+1);
            if ~isnan(curr)
                if isnan(left) && isnan(right)
                    thickness_map(row, col) = NaN;
                elseif ~isnan(left) && ~isnan(right)
                    neighbor_avg = (left + right) / 2;
                    if abs(curr - neighbor_avg) > 5
                        thickness_map(row, col) = NaN;
                    end
                end
            end
        end
    end

    filtered_map = thickness_map;
    for row = 2:size(thickness_map, 1)-1
        for col = 2:size(thickness_map, 2)-1
            center = thickness_map(row, col);
            if isnan(center)
                continue;
            end
            window = thickness_map(row-1:row+1, col-1:col+1);
            window_vals = window(~isnan(window));
            local_median = median(window_vals);
            if abs(center - local_median) > 10
                filtered_map(row, col) = NaN;
            end
        end
    end
    thickness_map = filtered_map;

    fig = figure;
    h_img = imagesc(thickness_map);
    valid_vals = thickness_map(~isnan(thickness_map));
    if ~isempty(valid_vals)
        clim = [min(valid_vals), max(valid_vals)];
        caxis(clim);
        avg_thickness = mean(valid_vals);
    else
        clim = [];
        avg_thickness = NaN;
        warning('No valid thickness values found. Skipping caxis adjustment.');
    end
    colormap jet;
    colorbar;
    xlabel('X (pixel position)');
    ylabel('Slice number');

    clean_filename = strrep(filename, '_', ' ');
    title({
        ['Phantom Thickness Map – ' clean_filename], ...
        ['Average Thickness = ' num2str(avg_thickness, '%.2f') ' px (click to view vertical profile)']
    });

    set(gca, 'YDir', 'normal');
    set(h_img, 'AlphaData', ~isnan(thickness_map));
    hold on;

    highlight_dot = scatter(NaN, NaN, 50, [1 0.4 0.7], 'filled');
    set(h_img, 'ButtonDownFcn', @(src, event) onClick(event, image_stack, highlight_dot, h_img, clim, tolerance, peakRatioThresh, minSeparation, maxSeparation));

    % Print status
    elapsedTime = toc;
    avgTimePerFile = elapsedTime / f;
    remainingTime = avgTimePerFile * (numFiles - f);
    fprintf('Completed %d of %d files (%.1f%%). Estimated time remaining: %.1f seconds.\n', ...
        f, numFiles, (f / numFiles) * 100, remainingTime);
end

totalTime = toc;
fprintf('\nAll files processed. Total time: %.1f seconds.\n', totalTime);

function onClick(event, image_stack, highlight_dot, h_img, clim, tolerance, peakRatioThresh, minSeparation, maxSeparation)
    persistent analysisFig

    ax = ancestor(event.Source, 'axes');
    coords = round(ax.CurrentPoint(1, 1:2));
    x = coords(1);
    y = coords(2);

    [height, width, slices] = size(image_stack);
    if x < 1 || x > width || y < 1 || y > slices
        return;
    end

    set(highlight_dot, 'XData', x, 'YData', y);
    img = image_stack(:, :, y);
    profile = img(:, x);

    [all_vals, all_locs] = findpeaks(profile, 'MinPeakProminence', tolerance);
    peak_vals = [];
    peak_locs = [];
    phantom_thickness = NaN;

    if numel(all_vals) >= 2
        global_max = max(all_vals);
        for i = 1:numel(all_vals)-1
            if all_vals(i) >= 0.9 * global_max
                found = false;
                for j = i+1:numel(all_vals)
                    thickness = abs(all_locs(j) - all_locs(i));
                    if all_vals(j) >= peakRatioThresh * all_vals(i) && ...
                       thickness >= minSeparation && thickness <= maxSeparation
                        peak_vals = [all_vals(i), all_vals(j)];
                        peak_locs = [all_locs(i), all_locs(j)];
                        phantom_thickness = thickness;
                        found = true;
                        break;
                    end
                end
                if ~found
                    for j = i+1:numel(all_vals)
                        thickness = abs(all_locs(j) - all_locs(i));
                        if all_vals(j) >= peakRatioThresh * all_vals(i) && ...
                           thickness >= minSeparation && thickness <= maxSeparation
                            peak_vals = [all_vals(i), all_vals(j)];
                            peak_locs = [all_locs(i), all_locs(j)];
                            phantom_thickness = thickness;
                            break;
                        end
                    end
                end
                break;
            end
        end
    end

    if ~isnan(phantom_thickness)
        thickness_str = ['Phantom Thickness = ' num2str(phantom_thickness) ' px'];
        thickness_map = get(h_img, 'CData');
        thickness_map(y, x) = phantom_thickness;
        set(h_img, 'CData', thickness_map, 'AlphaData', ~isnan(thickness_map));
        if ~isempty(clim)
            caxis(clim);
        end
    else
        thickness_str = 'Phantom Thickness = N/A';
    end

    if ~isempty(analysisFig) && isvalid(analysisFig)
        close(analysisFig);
    end

    analysisFig = figure('Name', ['Slice ' num2str(y) ', X = ' num2str(x)], ...
                         'NumberTitle', 'off', 'Position', [1000, 200, 800, 400]);

    subplot(1, 2, 1);
    imshow(img, [], 'InitialMagnification', 'fit');
    hold on;
    plot([x x], [1 size(img, 1)], '-', 'Color', [1 0.4 0.7], 'LineWidth', 1.5);
    if ~isempty(peak_locs)
        scatter(repmat(x, size(peak_locs)), peak_locs, 30, [0.8 0.1 0.4], 'filled');
    end
    title(['Slice ' num2str(y) ' with X = ' num2str(x)]);

    subplot(1, 2, 2);
    plot(profile, '-', 'Color', [1 0.4 0.7], 'LineWidth', 1.5);
    hold on;
    if ~isempty(peak_locs)
        scatter(peak_locs, peak_vals, 30, [0.8 0.1 0.4], 'filled');
    end
    xlabel('Y (vertical position)');
    ylabel('Intensity');
    title(['Vertical Intensity Profile (' thickness_str ')']);
    grid on;
end

