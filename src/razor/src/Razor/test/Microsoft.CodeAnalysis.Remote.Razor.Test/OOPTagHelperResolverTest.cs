﻿// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the MIT license. See License.txt in the project root for license information.

using System;
using System.Collections.Immutable;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Razor;
using Microsoft.AspNetCore.Razor.Language;
using Microsoft.AspNetCore.Razor.Serialization;
using Microsoft.AspNetCore.Razor.Telemetry;
using Microsoft.CodeAnalysis.Razor;
using Microsoft.CodeAnalysis.Razor.ProjectSystem;
using Microsoft.CodeAnalysis.Remote.Razor.Test;
using Moq;
using Xunit;
using Xunit.Abstractions;

namespace Microsoft.CodeAnalysis.Remote.Razor;

public partial class OOPTagHelperResolverTest : TagHelperDescriptorTestBase
{
    private readonly ProjectSnapshotProjectEngineFactory _engineFactory;
    private readonly Lazy<IProjectEngineFactory, ICustomProjectEngineFactoryMetadata>[] _customFactories;
    private readonly IFallbackProjectEngineFactory _fallbackFactory;
    private readonly HostProject _hostProject_For_2_0;
    private readonly HostProject _hostProject_For_NonSerializableConfiguration;
    private readonly ProjectSnapshotManagerBase _projectManager;
    private readonly Project _workspaceProject;
    private readonly Workspace _workspace;

    public OOPTagHelperResolverTest(ITestOutputHelper testOutput)
        : base(testOutput)
    {
        _hostProject_For_2_0 = new HostProject("Test.csproj", "/obj", FallbackRazorConfiguration.MVC_2_0, rootNamespace: null);
        _hostProject_For_NonSerializableConfiguration = new HostProject(
            "Test.csproj", "/obj",
            new ProjectSystemRazorConfiguration(RazorLanguageVersion.Version_2_1, "Random-0.1", Array.Empty<RazorExtension>()), rootNamespace: null);

        _customFactories = new Lazy<IProjectEngineFactory, ICustomProjectEngineFactoryMetadata>[]
        {
            new Lazy<IProjectEngineFactory, ICustomProjectEngineFactoryMetadata>(
                () => Mock.Of<IProjectEngineFactory>(MockBehavior.Strict),
                new ExportCustomProjectEngineFactoryAttribute("MVC-2.0") { SupportsSerialization = true, }),

            // We don't really use this factory, we just use it to ensure that the call is going to go out of process.
            new Lazy<IProjectEngineFactory, ICustomProjectEngineFactoryMetadata>(
                () => Mock.Of<IProjectEngineFactory>(MockBehavior.Strict),
                new ExportCustomProjectEngineFactoryAttribute("Test-2") { SupportsSerialization = false, }),
        };

        _fallbackFactory = new FallbackProjectEngineFactory();

        _workspace = new AdhocWorkspace();
        AddDisposable(_workspace);

        var info = ProjectInfo.Create(ProjectId.CreateNewId("Test"), VersionStamp.Default, "Test", "Test", LanguageNames.CSharp, filePath: "Test.csproj");
        _workspaceProject = _workspace.CurrentSolution.AddProject(info).GetProject(info.Id).AssumeNotNull();

        _projectManager = new TestProjectSnapshotManager(_workspace);
        _engineFactory = new DefaultProjectSnapshotProjectEngineFactory(_fallbackFactory, _customFactories);
    }

    [Fact]
    public async Task GetTagHelpersAsync_WithSerializableCustomFactory_GoesOutOfProcess()
    {
        // Arrange
        _projectManager.ProjectAdded(_hostProject_For_2_0);

        var projectSnapshot = _projectManager.GetLoadedProject(_hostProject_For_2_0.Key);

        var resolver = new TestResolver(_engineFactory, ErrorReporter, _workspace, NoOpTelemetryReporter.Instance)
        {
            OnResolveOutOfProcess = (f, p) =>
            {
                Assert.Same(_customFactories[0].Value, f);
                Assert.Same(projectSnapshot, p);

                return new(ImmutableArray<TagHelperDescriptor>.Empty);
            },
        };

        var result = await resolver.GetTagHelpersAsync(_workspaceProject, projectSnapshot, DisposalToken);

        // Assert
        Assert.Empty(result);
    }

    [Fact]
    public async Task GetTagHelpersAsync_WithNonSerializableCustomFactory_StaysInProcess()
    {
        // Arrange
        _projectManager.ProjectAdded(_hostProject_For_NonSerializableConfiguration);

        var projectSnapshot = _projectManager.GetLoadedProject(_hostProject_For_2_0.Key);

        var resolver = new TestResolver(_engineFactory, ErrorReporter, _workspace, NoOpTelemetryReporter.Instance)
        {
            OnResolveInProcess = (p) =>
            {
                Assert.Same(projectSnapshot, p);

                return new(ImmutableArray<TagHelperDescriptor>.Empty);
            },
        };

        var result = await resolver.GetTagHelpersAsync(_workspaceProject, projectSnapshot, DisposalToken);

        // Assert
        Assert.Empty(result);
    }

    [Fact]
    public async Task GetTagHelpersAsync_OperationCanceledException_DoesNotGetWrapped()
    {
        // Arrange
        _projectManager.ProjectAdded(_hostProject_For_2_0);

        var projectSnapshot = _projectManager.GetLoadedProject(_hostProject_For_2_0.Key);

        var cancellationToken = new CancellationToken(canceled: true);
        var resolver = new TestResolver(_engineFactory, ErrorReporter, _workspace, NoOpTelemetryReporter.Instance)
        {
            OnResolveInProcess = (p) =>
            {
                Assert.Same(projectSnapshot, p);

                return new(ImmutableArray<TagHelperDescriptor>.Empty);
            },
            OnResolveOutOfProcess = (f, p) =>
            {
                Assert.Same(projectSnapshot, p);

                throw new OperationCanceledException();
            }
        };

        await Assert.ThrowsAsync<OperationCanceledException>(async () => await resolver.GetTagHelpersAsync(_workspaceProject, projectSnapshot, cancellationToken));
    }

    [Fact]
    public void CalculateTagHelpersFromDelta_NewProject()
    {
        // Arrange
        var resolver = new TestResolver(_engineFactory, ErrorReporter, _workspace, NoOpTelemetryReporter.Instance);
        var initialDelta = new TagHelperDeltaResult(Delta: false, ResultId: 1, Project1TagHelpers, ImmutableArray<TagHelperDescriptor>.Empty);

        // Act
        var tagHelpers = resolver.PublicProduceTagHelpersFromDelta(Project1Id, lastResultId: -1, initialDelta);

        // Assert
        Assert.Equal(Project1TagHelpers, tagHelpers, TagHelperDescriptorComparer.Default);
    }

    [Fact]
    public void CalculateTagHelpersFromDelta_DeltaFailedToApplyToKnownProject()
    {
        // Arrange
        var resolver = new TestResolver(_engineFactory, ErrorReporter, _workspace, NoOpTelemetryReporter.Instance);
        var initialDelta = new TagHelperDeltaResult(Delta: false, ResultId: 1, Project1TagHelpers, ImmutableArray<TagHelperDescriptor>.Empty);
        resolver.PublicProduceTagHelpersFromDelta(Project1Id, lastResultId: -1, initialDelta);
        var newTagHelperSet = ImmutableArray.Create(TagHelper1_Project1);
        var failedDeltaApplication = new TagHelperDeltaResult(Delta: false, initialDelta.ResultId + 1, newTagHelperSet, ImmutableArray<TagHelperDescriptor>.Empty);

        // Act
        var tagHelpers = resolver.PublicProduceTagHelpersFromDelta(Project1Id, initialDelta.ResultId, failedDeltaApplication);

        // Assert
        Assert.Equal(newTagHelperSet, tagHelpers, TagHelperDescriptorComparer.Default);
    }

    [Fact]
    public void CalculateTagHelpersFromDelta_NoopResult()
    {
        // Arrange
        var resolver = new TestResolver(_engineFactory, ErrorReporter, _workspace, NoOpTelemetryReporter.Instance);
        var initialDelta = new TagHelperDeltaResult(Delta: false, ResultId: 1, Project1TagHelpers, ImmutableArray<TagHelperDescriptor>.Empty);
        resolver.PublicProduceTagHelpersFromDelta(Project1Id, lastResultId: -1, initialDelta);
        var noopDelta = new TagHelperDeltaResult(Delta: true, initialDelta.ResultId, ImmutableArray<TagHelperDescriptor>.Empty, ImmutableArray<TagHelperDescriptor>.Empty);

        // Act
        var tagHelpers = resolver.PublicProduceTagHelpersFromDelta(Project1Id, initialDelta.ResultId, noopDelta);

        // Assert
        Assert.Equal(Project1TagHelpers, tagHelpers, TagHelperDescriptorComparer.Default);
    }

    [Fact]
    public void CalculateTagHelpersFromDelta_ReplacedTagHelpers()
    {
        // Arrange
        var resolver = new TestResolver(_engineFactory, ErrorReporter, _workspace, NoOpTelemetryReporter.Instance);
        var initialDelta = new TagHelperDeltaResult(Delta: false, ResultId: 1, Project1TagHelpers, ImmutableArray<TagHelperDescriptor>.Empty);
        resolver.PublicProduceTagHelpersFromDelta(Project1Id, lastResultId: -1, initialDelta);
        var changedDelta = new TagHelperDeltaResult(Delta: true, initialDelta.ResultId + 1, ImmutableArray.Create(TagHelper2_Project2), ImmutableArray.Create(TagHelper2_Project1));

        // Act
        var tagHelpers = resolver.PublicProduceTagHelpersFromDelta(Project1Id, initialDelta.ResultId, changedDelta);

        // Assert
        Assert.Equal(new[] { TagHelper1_Project1, TagHelper2_Project2 }, tagHelpers.OrderBy(th => th.Name));
    }
}
