﻿// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.CodeAnalysis.CodeActions;
using Microsoft.CodeAnalysis.CodeFixes;
using Microsoft.CodeAnalysis.Diagnostics;
using Microsoft.CodeAnalysis.Editing;
using Microsoft.CodeAnalysis.Formatting;
using Microsoft.CodeAnalysis.LanguageService;
using Microsoft.CodeAnalysis.Shared.Extensions;
using Roslyn.Utilities;

namespace Microsoft.CodeAnalysis.UseObjectInitializer
{
    internal abstract class AbstractUseObjectInitializerCodeFixProvider<
        TSyntaxKind,
        TExpressionSyntax,
        TStatementSyntax,
        TObjectCreationExpressionSyntax,
        TMemberAccessExpressionSyntax,
        TAssignmentStatementSyntax,
        TVariableDeclaratorSyntax>
        : SyntaxEditorBasedCodeFixProvider
        where TSyntaxKind : struct
        where TExpressionSyntax : SyntaxNode
        where TStatementSyntax : SyntaxNode
        where TObjectCreationExpressionSyntax : TExpressionSyntax
        where TMemberAccessExpressionSyntax : TExpressionSyntax
        where TAssignmentStatementSyntax : TStatementSyntax
        where TVariableDeclaratorSyntax : SyntaxNode
    {
        public override ImmutableArray<string> FixableDiagnosticIds
            => ImmutableArray.Create(IDEDiagnosticIds.UseObjectInitializerDiagnosticId);

        protected override bool IncludeDiagnosticDuringFixAll(Diagnostic diagnostic)
            => !diagnostic.Descriptor.ImmutableCustomTags().Contains(WellKnownDiagnosticTags.Unnecessary);

        public override Task RegisterCodeFixesAsync(CodeFixContext context)
        {
            RegisterCodeFix(context, AnalyzersResources.Object_initialization_can_be_simplified, nameof(AnalyzersResources.Object_initialization_can_be_simplified));
            return Task.CompletedTask;
        }

        protected override async Task FixAllAsync(
            Document document, ImmutableArray<Diagnostic> diagnostics,
            SyntaxEditor editor, CodeActionOptionsProvider fallbackOptions, CancellationToken cancellationToken)
        {
            // Fix-All for this feature is somewhat complicated.  As Object-Initializers 
            // could be arbitrarily nested, we have to make sure that any edits we make
            // to one Object-Initializer are seen by any higher ones.  In order to do this
            // we actually process each object-creation-node, one at a time, rewriting
            // the tree for each node.  In order to do this effectively, we use the '.TrackNodes'
            // feature to keep track of all the object creation nodes as we make edits to
            // the tree.  If we didn't do this, then we wouldn't be able to find the 
            // second object-creation-node after we make the edit for the first one.
            var syntaxFacts = document.GetLanguageService<ISyntaxFactsService>();

            var originalRoot = editor.OriginalRoot;
            var originalObjectCreationNodes = new Stack<TObjectCreationExpressionSyntax>();
            foreach (var diagnostic in diagnostics)
            {
                var objectCreation = (TObjectCreationExpressionSyntax)originalRoot.FindNode(
                    diagnostic.AdditionalLocations[0].SourceSpan, getInnermostNodeForTie: true);
                originalObjectCreationNodes.Push(objectCreation);
            }

            // We're going to be continually editing this tree.  Track all the nodes we
            // care about so we can find them across each edit.
            document = document.WithSyntaxRoot(originalRoot.TrackNodes(originalObjectCreationNodes));

            var semanticModel = await document.GetSemanticModelAsync(cancellationToken).ConfigureAwait(false);
            var currentRoot = await document.GetRequiredSyntaxRootAsync(cancellationToken).ConfigureAwait(false);

            while (originalObjectCreationNodes.Count > 0)
            {
                var originalObjectCreation = originalObjectCreationNodes.Pop();
                var objectCreation = currentRoot.GetCurrentNodes(originalObjectCreation).Single();

                var matches = UseNamedMemberInitializerAnalyzer<TExpressionSyntax, TStatementSyntax, TObjectCreationExpressionSyntax, TMemberAccessExpressionSyntax, TAssignmentStatementSyntax, TVariableDeclaratorSyntax>.Analyze(
                    semanticModel, syntaxFacts, objectCreation, cancellationToken);

                if (matches.IsDefaultOrEmpty)
                    continue;

                var statement = objectCreation.FirstAncestorOrSelf<TStatementSyntax>();
                Contract.ThrowIfNull(statement);

                var newStatement = GetNewStatement(statement, objectCreation, matches)
                    .WithAdditionalAnnotations(Formatter.Annotation);

                var subEditor = new SyntaxEditor(currentRoot, document.Project.Solution.Services);

                subEditor.ReplaceNode(statement, newStatement);
                foreach (var match in matches)
                {
                    subEditor.RemoveNode(match.Statement, SyntaxRemoveOptions.KeepUnbalancedDirectives);
                }

                document = document.WithSyntaxRoot(subEditor.GetChangedRoot());
                semanticModel = await document.GetSemanticModelAsync(cancellationToken).ConfigureAwait(false);
                currentRoot = await document.GetRequiredSyntaxRootAsync(cancellationToken).ConfigureAwait(false);
            }

            editor.ReplaceNode(editor.OriginalRoot, currentRoot);
        }

        protected abstract TStatementSyntax GetNewStatement(
            TStatementSyntax statement, TObjectCreationExpressionSyntax objectCreation,
            ImmutableArray<Match<TExpressionSyntax, TStatementSyntax, TMemberAccessExpressionSyntax, TAssignmentStatementSyntax>> matches);
    }
}
