﻿// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Microsoft.Extensions.FileSystemGlobbing;
using Xunit;
using Xunit.Abstractions;

namespace Microsoft.DotNet.SourceBuild.SmokeTests
{
    internal class BaselineHelper
    {
        private const string VersionPlaceholder = "x.y.z";
        private const string VersionPlaceholderMatchingPattern = "*.*.*"; // wildcard pattern used to match on the version represented by the placeholder
        private const string NetTfmPlaceholder = "netx.y";
        private const string NetTfmPlaceholderMatchingPattern = "net*.*"; // wildcard pattern used to match on the version represented by the placeholder

        public static void CompareEntries(string baselineFileName, IOrderedEnumerable<string> actualEntries)
        {
            IEnumerable<string> baseline = File.ReadAllLines(GetBaselineFilePath(baselineFileName));
            string[] missingEntries = actualEntries.Except(baseline).ToArray();
            string[] extraEntries = baseline.Except(actualEntries).ToArray();

            string? message = null;
            if (missingEntries.Length > 0)
            {
                message = $"Missing entries in '{baselineFileName}' baseline: {Environment.NewLine}{string.Join(Environment.NewLine, missingEntries)}{Environment.NewLine}{Environment.NewLine}";
            }

            if (extraEntries.Length > 0)
            {
                message += $"Extra entries in '{baselineFileName}' baseline: {Environment.NewLine}{string.Join(Environment.NewLine, extraEntries)}{Environment.NewLine}{Environment.NewLine}";
            }

            Assert.Null(message);
        }

        public static void CompareBaselineContents(string baselineFileName, string actualContents, ITestOutputHelper outputHelper, bool warnOnDiffs = false)
        {
            string actualFilePath = Path.Combine(DotNetHelper.LogsDirectory, $"Updated{baselineFileName}");
            File.WriteAllText(actualFilePath, actualContents);

            CompareFiles(GetBaselineFilePath(baselineFileName), actualFilePath, outputHelper, warnOnDiffs);
        }

        public static void CompareFiles(string expectedFilePath, string actualFilePath, ITestOutputHelper outputHelper, bool warnOnDiffs = false)
        {
            string baselineFileText = File.ReadAllText(expectedFilePath).Trim();
            string actualFileText = File.ReadAllText(actualFilePath).Trim();

            string? message = null;

            if (baselineFileText != actualFileText)
            {
                // Retrieve a diff in order to provide a UX which calls out the diffs.
                string diff = DiffFiles(expectedFilePath, actualFilePath, outputHelper);
                string prefix = warnOnDiffs ? "##vso[task.logissue type=warning;]" : string.Empty;
                message = $"{Environment.NewLine}{prefix}Expected file '{expectedFilePath}' does not match actual file '{actualFilePath}`.  {Environment.NewLine}"
                    + $"{diff}{Environment.NewLine}";

                if (warnOnDiffs)
                {
                    outputHelper.WriteLine(message);
                    outputHelper.WriteLine("##vso[task.complete result=SucceededWithIssues;]");
                }
            }

            if (!warnOnDiffs)
            {
                Assert.Null(message);
            }
        }

        public static string DiffFiles(string file1Path, string file2Path, ITestOutputHelper outputHelper)
        {
            (Process Process, string StdOut, string StdErr) diffResult =
                ExecuteHelper.ExecuteProcess("git", $"diff --no-index {file1Path} {file2Path}", outputHelper);

            return diffResult.StdOut;
        }

        public static string GetAssetsDirectory() => Path.Combine(Directory.GetCurrentDirectory(), "assets");

        public static string GetBaselineFilePath(string baselineFileName) => Path.Combine(GetAssetsDirectory(), "baselines", baselineFileName);

        public static string RemoveNetTfmPaths(string source)
        {
            string pathSeparator = Regex.Escape(Path.DirectorySeparatorChar.ToString());
            Regex netTfmRegex = new($"{pathSeparator}net[1-9]+\\.[0-9]+{pathSeparator}");
            return netTfmRegex.Replace(source, $"{Path.DirectorySeparatorChar}{NetTfmPlaceholder}{Path.DirectorySeparatorChar}");
        }

        public static string RemoveRids(string diff, bool isPortable = false) =>
            isPortable ? diff.Replace(Config.PortableRid, "portable-rid") : diff.Replace(Config.TargetRid, "banana-rid");

        public static string RemoveVersions(string source)
        {
            // Remove semantic versions
            // Regex source: https://semver.org/#is-there-a-suggested-regular-expression-regex-to-check-a-semver-string
            Regex semanticVersionRegex = new(
                $"(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)"
                + $"(?:-((?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\\.(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*))*))"
                + $"?(?:\\+([0-9a-zA-Z-]+(?:\\.[0-9a-zA-Z-]+)*))?");
            string result = semanticVersionRegex.Replace(source, VersionPlaceholder);

            return RemoveNetTfmPaths(result);
        }

        /// <summary>
        /// This returns a <see cref="Matcher"/> that can be used to match on a path whose versions have been removed via
        /// <see cref="RemoveVersions(string)"/>.
        /// </summary>
        public static Matcher GetFileMatcherFromPath(string path)
        {
            path = path
                .Replace(VersionPlaceholder, VersionPlaceholderMatchingPattern)
                .Replace(NetTfmPlaceholder, NetTfmPlaceholderMatchingPattern);
            Matcher matcher = new();
            matcher.AddInclude(path);
            return matcher;
        }
    }
}
