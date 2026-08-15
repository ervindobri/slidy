//
//  MediaActionsView.swift
//  Slidy
//
//  Created by Ervin Dobri on 2026. 08. 14..
//

import SwiftUI



struct MediaActions: View {
    // TODO: add glass container merged
    var body: some View {
        HStack(spacing: 16.0) {
            RotateAction()
            DeleteAction()
        }
        // Centred in the bar rather than laid out from the leading edge, so the
        // pair stays under the thumb on a phone and doesn't drift left of the
        // page indicator.
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32.0)
    }
}
/// The face of a bottom-bar button. One size on both branches: the glass and
/// non-glass paths used to draw the same icon at 24pt and 13pt, so the bar
/// changed size depending on what the OS supported.
private struct ActionIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 26, height: 26)
            .padding(8.0)
    }
}

struct RotateAction: View {
    @Environment(MediaLibrary.self) private var library
    @Namespace private var namespace

    var body: some View {
        if (library.currentItem?.kind == MediaKind.video) {
            // empty view
        }
        else {


        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer {


                Button {
                    library.rotateImage()
                } label: {
                    ActionIcon(systemName: "arrow.clockwise")
            }
            .cornerRadius(99.9)
            .buttonStyle(.smallLiquidGlass)
            }
        } else {
            // Fallback on earlier versions
            Button {
                library.rotateImage()
            } label: {
                ActionIcon(systemName: "arrow.clockwise")
            }.cornerRadius(99.9)
        }
        }
    }
}

struct DeleteAction: View {
    @Environment(MediaLibrary.self) private var library
    @Namespace private var namespace
    
    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer {
                
            
            Button {library.deleteCurrent()  } label: {
                ActionIcon(systemName: "trash")
            }
            .cornerRadius(99.9)
            .buttonStyle(.smallLiquidGlass)
            }
        } else {
            // Fallback on earlier versions
            Button {library.deleteCurrent()  }
            label: {
                ActionIcon(systemName: "trash")
            }.cornerRadius(99.9)
                .frame(alignment: Alignment.center)
        }
    }
}


#Preview {
    MediaActions()
}
