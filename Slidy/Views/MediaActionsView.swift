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
        HStack(spacing: 12.0) {
            RotateAction()
            DeleteAction()
        }.padding(EdgeInsets(top: 0, leading: 32.0, bottom: 0.0, trailing: 32.0))
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
                Image(systemName: "arrow.clockwise")
                    .padding(6.0)
                    .font(.system(size: 24, weight: .semibold))
            }
            .cornerRadius(99.9)
            .buttonStyle(.smallLiquidGlass)
            }
        } else {
            // Fallback on earlier versions
            Button {
                library.rotateImage()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .padding(6.0)
                    .font(.system(size: 13, weight: .semibold))
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
                Image(systemName: "trash")
                    .padding(6.0)
                    .font(.system(size: 24, weight: .semibold))
            }
            .cornerRadius(99.9)
            .buttonStyle(.smallLiquidGlass)
            }
        } else {
            // Fallback on earlier versions
            Button {library.deleteCurrent()  }
            label: {
                Image(systemName: "trash")
                    .padding(6.0)
                    .font(.system(size: 13, weight: .semibold))
            }.cornerRadius(99.9)
                .frame(alignment: Alignment.center)
        }
    }
}


#Preview {
    MediaActions()
}
