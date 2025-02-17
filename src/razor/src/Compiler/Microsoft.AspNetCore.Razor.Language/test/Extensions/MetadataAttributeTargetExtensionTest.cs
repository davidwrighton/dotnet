﻿// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

#nullable disable

using Microsoft.AspNetCore.Razor.Language.CodeGeneration;
using Xunit;

namespace Microsoft.AspNetCore.Razor.Language.Extensions;

public class MetadataAttributeTargetExtensionTest
{
    [Fact]
    public void WriteRazorCompiledItemAttribute_RendersCorrectly()
    {
        // Arrange
        var extension = new MetadataAttributeTargetExtension()
        {
            CompiledItemAttributeName = "global::TestItem",
        };
        var context = TestCodeRenderingContext.CreateRuntime();

        var node = new RazorCompiledItemAttributeIntermediateNode()
        {
            TypeName = "Foo.Bar",
            Kind = "test",
            Identifier = "Foo/Bar",
        };

        // Act
        extension.WriteRazorCompiledItemAttribute(context, node);

        // Assert
        var csharp = context.CodeWriter.GenerateCode();
        Assert.Equal(
@"[assembly: global::TestItem(typeof(Foo.Bar), @""test"", @""Foo/Bar"")]
",
            csharp,
            ignoreLineEndingDifferences: true);
    }

    [Fact]
    public void WriteRazorSourceChecksumAttribute_RendersCorrectly()
    {
        // Arrange
        var extension = new MetadataAttributeTargetExtension()
        {
            SourceChecksumAttributeName = "global::TestChecksum",
        };
        var context = TestCodeRenderingContext.CreateRuntime();

        var node = new RazorSourceChecksumAttributeIntermediateNode()
        {
            ChecksumAlgorithm = "SHA256",
            Checksum = new byte[] { (byte)'t', (byte)'e', (byte)'s', (byte)'t', },
            Identifier = "Foo/Bar",
        };

        // Act
        extension.WriteRazorSourceChecksumAttribute(context, node);

        // Assert
        var csharp = context.CodeWriter.GenerateCode();
        Assert.Equal(
@"[global::TestChecksum(@""SHA256"", @""74657374"", @""Foo/Bar"")]
",
            csharp,
            ignoreLineEndingDifferences: true);
    }

    [Fact]
    public void WriteRazorCompiledItemAttributeMetadata_RendersCorrectly()
    {
        // Arrange
        var extension = new MetadataAttributeTargetExtension()
        {
            CompiledItemMetadataAttributeName = "global::TestItemMetadata",
        };
        var context = TestCodeRenderingContext.CreateRuntime();

        var node = new RazorCompiledItemMetadataAttributeIntermediateNode
        {
            Key = "key",
            Value = "value",
        };

        // Act
        extension.WriteRazorCompiledItemMetadataAttribute(context, node);

        // Assert
        var csharp = context.CodeWriter.GenerateCode().Trim();
        Assert.Equal(
"[global::TestItemMetadata(\"key\", \"value\")]",
            csharp,
            ignoreLineEndingDifferences: true);
    }

    [Fact]
    public void WriteRazorCompiledItemAttributeMetadata_EscapesKeysAndValuesCorrectly()
    {
        // Arrange
        var extension = new MetadataAttributeTargetExtension()
        {
            CompiledItemMetadataAttributeName = "global::TestItemMetadata",
        };
        var context = TestCodeRenderingContext.CreateRuntime();

        var node = new RazorCompiledItemMetadataAttributeIntermediateNode
        {
            Key = "\"test\" key",
            Value = @"""test"" value",
        };

        // Act
        extension.WriteRazorCompiledItemMetadataAttribute(context, node);

        // Assert
        var csharp = context.CodeWriter.GenerateCode().Trim();
        Assert.Equal(
"[global::TestItemMetadata(\"\\\"test\\\" key\", \"\\\"test\\\" value\")]",
            csharp,
            ignoreLineEndingDifferences: true);
    }
}
