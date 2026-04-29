//
//  HomeMapWidget.swift
//  bilu
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Appearance helper

/// Spicy Red in light mode, Mango Orange in dark mode — mirrors the map's own muted dark style.
private func mapAccent(dark: Bool, alpha: CGFloat) -> UIColor {
    dark
        ? UIColor(red: 255/255, green: 149/255, blue: 0/255,   alpha: alpha)  // #FF9500 mango orange
        : UIColor(red: 255/255, green: 59/255,  blue: 48/255,  alpha: alpha)  // #FF3B30 spicy red
}

// MARK: - Annotation classes

private final class CenterAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(_ coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

// MARK: - Center pin view (56×56 hit target, 22×22 visual dot)

private final class CenterPinView: MKAnnotationView {
    static let reuseID = "CenterPin"
    private let ring = UIView(frame: CGRect(x: 17, y: 17, width: 22, height: 22))
    private let dot  = UIView(frame: CGRect(x: 22, y: 22, width: 12, height: 12))

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 56, height: 56)
        isUserInteractionEnabled = true
        canShowCallout = false
        backgroundColor = .clear
        ring.layer.cornerRadius = 11
        addSubview(ring)
        dot.layer.cornerRadius = 6
        dot.layer.borderWidth = 2.5
        dot.layer.borderColor = UIColor.white.cgColor
        dot.layer.shadowColor = UIColor.black.cgColor
        dot.layer.shadowOpacity = 0.25
        dot.layer.shadowRadius = 3
        dot.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(dot)
        applyColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous) { applyColors() }
    }

    private func applyColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        ring.backgroundColor = mapAccent(dark: dark, alpha: 0.18)
        dot.backgroundColor  = mapAccent(dark: dark, alpha: 1)
    }
}

// MARK: - Arc handle view
// Full-map transparent overlay. CAShapeLayer draws a thick arc on the east side.
// hitTest only responds to touches near the arc — all others fall through to the map.

private final class ArcHandleView: UIView {
    var mapCenter: CLLocationCoordinate2D = CLLocationCoordinate2D()
    var radiusMeters: Double = 0
    /// True while the user is dragging the center pin — shrinks arc to a small indicator
    var isDraggingCenter: Bool = false {
        didSet { guard oldValue != isDraggingCenter else { return }; setNeedsLayout() }
    }
    weak var mapView: MKMapView?

    /// Draws the dashed radius ring — replaces MKCircle overlay so both layers update in sync
    private let circleLayer = CAShapeLayer()
    /// Draws the grabbable arc handle on the east side
    private let arcLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false  // purely visual; all gestures are on mapView
        backgroundColor = .clear
        // Circle underneath arc
        circleLayer.fillColor = UIColor.clear.cgColor
        circleLayer.lineWidth = 1.5
        circleLayer.lineDashPattern = [6, 4]
        circleLayer.lineCap = .butt
        layer.addSublayer(circleLayer)
        // Arc on top
        arcLayer.fillColor = UIColor.clear.cgColor
        arcLayer.lineCap = .round
        layer.addSublayer(arcLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        circleLayer.frame = bounds
        arcLayer.frame = bounds
        updateArc()
    }

    func updateArc() {
        guard let mapView = mapView, radiusMeters > 0 else {
            circleLayer.path = nil; arcLayer.path = nil; return
        }
        let (centerPt, radiusPx) = screenMetrics(in: mapView)
        guard radiusPx > 2 else { circleLayer.path = nil; arcLayer.path = nil; return }

        let dark = traitCollection.userInterfaceStyle == .dark

        // --- Circle ring (replaces MKCircle overlay) ---
        let fullCircle = UIBezierPath(arcCenter: centerPt, radius: radiusPx,
                                      startAngle: 0, endAngle: .pi * 2, clockwise: true)
        circleLayer.path = fullCircle.cgPath
        circleLayer.strokeColor = mapAccent(dark: dark, alpha: 0.70).cgColor
        // Simulate fill with a separate filled circle path at low opacity
        let fillCircle = UIBezierPath(arcCenter: centerPt, radius: radiusPx,
                                      startAngle: 0, endAngle: .pi * 2, clockwise: true)
        fillCircle.close()
        // Use circleLayer for stroke only; add fill via a sublayer approach — simpler: just set fillColor
        circleLayer.fillColor = mapAccent(dark: dark, alpha: 0.10).cgColor
        circleLayer.path = fillCircle.cgPath  // closed path so fill works

        // --- Arc handle ---
        if isDraggingCenter {
            let path = UIBezierPath(arcCenter: centerPt, radius: radiusPx,
                                    startAngle: -.pi / 9, endAngle: .pi / 9, clockwise: true)
            arcLayer.path = path.cgPath
            arcLayer.lineWidth = 5
            arcLayer.strokeColor = mapAccent(dark: dark, alpha: 0.35).cgColor
        } else {
            let path = UIBezierPath(arcCenter: centerPt, radius: radiusPx,
                                    startAngle: -.pi / 3, endAngle: .pi / 3, clockwise: true)
            arcLayer.path = path.cgPath
            arcLayer.lineWidth = 16
            arcLayer.strokeColor = mapAccent(dark: dark, alpha: 0.82).cgColor
        }
    }

    /// Center in view-local screen points and radius in screen points
    func screenMetrics(in mapView: MKMapView) -> (CGPoint, CGFloat) {
        let centerPt = mapView.convert(mapCenter, toPointTo: self)
        let lngDelta = radiusMeters / (cos(mapCenter.latitude * .pi / 180) * 111_320.0)
        let eastCoord = CLLocationCoordinate2D(latitude: mapCenter.latitude,
                                               longitude: mapCenter.longitude + lngDelta)
        let eastPt = mapView.convert(eastCoord, toPointTo: self)
        let radiusPx = hypot(eastPt.x - centerPt.x, eastPt.y - centerPt.y)
        return (centerPt, radiusPx)
    }

    /// Checks whether a screen point falls in the grabbable arc zone
    func isInArcZone(_ point: CGPoint, centerPt: CGPoint, radiusPx: CGFloat) -> Bool {
        let dx = point.x - centerPt.x
        let dy = point.y - centerPt.y
        let dist = hypot(dx, dy)
        let angle = atan2(dy, dx)          // 0 = east, ± going toward south/north
        let tolerance: CGFloat = 48        // ±48pt radial band — wide enough to grab easily
        let angularRange: CGFloat = .pi * 5 / 12   // ±75°
        return abs(dist - radiusPx) < tolerance && abs(angle) < angularRange
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let mapView = mapView, radiusMeters > 0 else { return nil }
        let (centerPt, radiusPx) = screenMetrics(in: mapView)
        return isInArcZone(point, centerPt: centerPt, radiusPx: radiusPx) ? self : nil
    }
}

// MARK: - UIViewRepresentable

private struct InteractiveMapView: UIViewRepresentable {
    @Binding var radiusMiles: Double
    @Binding var center: CLLocationCoordinate2D
    let isExpanded: Bool
    let showRadius: Bool
    let onDragBegan: () -> Void
    let onDragEnded: () -> Void
    let onMapTapped: () -> Void
    let onCenterChanged: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Map span in degrees. Uses a sqrt curve so small radii zoom in tightly
    /// and large radii zoom out gradually — prevents the map from flying out too fast.
    static func spanForRadius(_ miles: Double) -> Double {
        max(0.08, 0.10 * sqrt(miles))
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsUserLocation = false
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isRotateEnabled = false
        mapView.isUserInteractionEnabled = false

        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = config

        mapView.setRegion(
            MKCoordinateRegion(center: center,
                               span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)),
            animated: false
        )

        // Center annotation
        let centerAnn = CenterAnnotation(center)
        mapView.addAnnotation(centerAnn)
        context.coordinator.centerAnnotation = centerAnn
        context.coordinator.currentCenter = center
        context.coordinator.mapView = mapView

        // Tap to collapse (UIKit — enabled when expanded)
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleMapTap))
        tap.isEnabled = false
        mapView.addGestureRecognizer(tap)
        context.coordinator.collapseTap = tap

        // Pan anywhere inside radius circle (enabled when expanded)
        let mapPan = UIPanGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleMapPan(_:)))
        mapPan.delegate = context.coordinator
        mapPan.isEnabled = false
        mapView.addGestureRecognizer(mapPan)
        context.coordinator.mapPanGesture = mapPan

        // Arc radius handle (full-map overlay, only activates via hitTest)
        let arcView = ArcHandleView(frame: mapView.bounds)
        arcView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arcView.mapView = mapView
        arcView.isHidden = true
        mapView.addSubview(arcView)
        context.coordinator.arcHandleView = arcView

        // Arc radius pan — on mapView (not arcView) so it doesn't conflict with annotation hit-testing.
        // gestureRecognizerShouldBegin limits this gesture to arc-zone touches only.
        let arcPan = UIPanGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleRadiusPan(_:)))
        arcPan.delegate = context.coordinator
        mapView.addGestureRecognizer(arcPan)
        context.coordinator.arcPanGesture = arcPan

        // collapseTap must wait for both pan gestures to fail — prevents the map from
        // collapsing mid-drag when the user is moving the pin or resizing the radius.
        tap.require(toFail: mapPan)
        tap.require(toFail: arcPan)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coord = context.coordinator
        coord.parent = self   // keep coordinator in sync — gesture handlers read parent.isExpanded etc.
        mapView.isUserInteractionEnabled = true   // always on — tap must reach UIKit to expand
        coord.collapseTap?.isEnabled = true        // always on — fires expand when collapsed, collapse when expanded
        coord.mapPanGesture?.isEnabled = isExpanded

        // Zoom transition on expand/collapse
        if isExpanded != coord.wasExpanded {
            let span: Double = isExpanded ? Self.spanForRadius(radiusMiles) : 0.05
            mapView.setRegion(
                MKCoordinateRegion(center: coord.currentCenter,
                                   span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)),
                animated: true
            )
            coord.wasExpanded = isExpanded
        }

        guard isExpanded, showRadius else {
            coord.arcHandleView?.isHidden = true
            return
        }

        let liveCenter = coord.currentCenter
        let radiusMeters = radiusMiles * 1609.34

        // Arc view draws both the circle ring and the arc handle — no MKCircle overlay needed
        let arc = coord.arcHandleView
        arc?.isHidden = false
        arc?.mapCenter = liveCenter
        arc?.radiusMeters = radiusMeters
        arc?.setNeedsLayout()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: InteractiveMapView
        weak var mapView: MKMapView?
        var centerAnnotation: CenterAnnotation?
        var arcHandleView: ArcHandleView?
        var collapseTap: UITapGestureRecognizer?
        var mapPanGesture: UIPanGestureRecognizer?
        var arcPanGesture: UIPanGestureRecognizer?
        var wasExpanded = false
        var currentCenter = CLLocationCoordinate2D(latitude: 34.0224, longitude: -118.2851)

        init(_ parent: InteractiveMapView) {
            self.parent = parent
            self.currentCenter = parent.center
        }

        // Called every frame while the map region is animating — keeps circle+arc locked in place
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            arcHandleView?.setNeedsLayout()
        }

        // MARK: Annotation views

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            guard annotation is CenterAnnotation else { return nil }
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: CenterPinView.reuseID) as? CenterPinView)
                ?? CenterPinView(annotation: annotation, reuseIdentifier: CenterPinView.reuseID)
            view.annotation = annotation
            if view.gestureRecognizers?.contains(where: { $0 is UIPanGestureRecognizer }) != true {
                view.addGestureRecognizer(
                    UIPanGestureRecognizer(target: self, action: #selector(handleCenterPan(_:))))
            }
            return view
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let mapView = mapView else { return false }
            let pt = gestureRecognizer.location(in: mapView)

            // Compute whether the touch is in the arc handle zone (only matters when arc is visible).
            let inArcZone: Bool
            if parent.showRadius, let arc = arcHandleView {
                let (centerPt, radiusPx) = arc.screenMetrics(in: mapView)
                inArcZone = arc.isInArcZone(pt, centerPt: centerPt, radiusPx: radiusPx)
            } else {
                inArcZone = false
            }

            if gestureRecognizer === mapPanGesture {
                guard parent.isExpanded else { return false }
                return !inArcZone   // yield to arc gesture when user grabs the handle
            }
            if gestureRecognizer === arcPanGesture {
                return parent.isExpanded && parent.showRadius && inArcZone
            }
            return true
        }

        // MARK: Gestures

        @objc func handleMapTap() { parent.onMapTapped() }

        /// Center pan via the annotation view
        @objc func handleCenterPan(_ gesture: UIPanGestureRecognizer) {
            guard parent.isExpanded, let mapView = mapView else { return }
            let pt = gesture.location(in: mapView)
            let newCoord = mapView.convert(pt, toCoordinateFrom: mapView)

            switch gesture.state {
            case .began:
                parent.onDragBegan()
                arcHandleView?.isDraggingCenter = true
            case .changed:
                currentCenter = newCoord
                centerAnnotation?.coordinate = newCoord
                redrawCircle(in: mapView, center: newCoord, radiusMeters: parent.radiusMiles * 1609.34)
                panToEdgeIfNeeded(touchPoint: pt, in: mapView)
            case .ended, .cancelled:
                arcHandleView?.isDraggingCenter = false
                currentCenter = newCoord
                centerAnnotation?.coordinate = newCoord
                redrawCircle(in: mapView, center: newCoord, radiusMeters: parent.radiusMiles * 1609.34)
                mapView.setRegion(
                    MKCoordinateRegion(center: newCoord,
                                       span: MKCoordinateSpan(latitudeDelta: InteractiveMapView.spanForRadius(parent.radiusMiles), longitudeDelta: InteractiveMapView.spanForRadius(parent.radiusMiles))),
                    animated: true
                )
                parent.center = newCoord
                parent.onCenterChanged(newCoord)
                parent.onDragEnded()
            default: break
            }
        }

        /// Center pan via tap-anywhere-in-circle (map-level gesture)
        @objc func handleMapPan(_ gesture: UIPanGestureRecognizer) {
            guard parent.isExpanded, let mapView = mapView else { return }
            let pt = gesture.location(in: mapView)
            let newCoord = mapView.convert(pt, toCoordinateFrom: mapView)

            switch gesture.state {
            case .began:
                parent.onDragBegan()
                arcHandleView?.isDraggingCenter = true
            case .changed:
                currentCenter = newCoord
                centerAnnotation?.coordinate = newCoord
                redrawCircle(in: mapView, center: newCoord, radiusMeters: parent.radiusMiles * 1609.34)
                panToEdgeIfNeeded(touchPoint: pt, in: mapView)
            case .ended, .cancelled:
                arcHandleView?.isDraggingCenter = false
                currentCenter = newCoord
                centerAnnotation?.coordinate = newCoord
                redrawCircle(in: mapView, center: newCoord, radiusMeters: parent.radiusMiles * 1609.34)
                mapView.setRegion(
                    MKCoordinateRegion(center: newCoord,
                                       span: MKCoordinateSpan(latitudeDelta: InteractiveMapView.spanForRadius(parent.radiusMiles), longitudeDelta: InteractiveMapView.spanForRadius(parent.radiusMiles))),
                    animated: true
                )
                parent.center = newCoord
                parent.onCenterChanged(newCoord)
                parent.onDragEnded()
            default: break
            }
        }

        /// Drag the arc handle to resize the radius
        @objc func handleRadiusPan(_ gesture: UIPanGestureRecognizer) {
            guard parent.showRadius, let mapView = mapView else { return }
            let pt = gesture.location(in: mapView)
            let touchCoord = mapView.convert(pt, toCoordinateFrom: mapView)
            let dist = CLLocation(latitude: currentCenter.latitude, longitude: currentCenter.longitude)
                .distance(from: CLLocation(latitude: touchCoord.latitude, longitude: touchCoord.longitude)) / 1609.34
            let clamped = min(max(dist, 0.5), 50.0)

            switch gesture.state {
            case .began:
                parent.onDragBegan()
                parent.radiusMiles = clamped
            case .changed:
                parent.radiusMiles = clamped
                arcHandleView?.radiusMeters = clamped * 1609.34
                arcHandleView?.setNeedsLayout()
                mapView.setRegion(
                    MKCoordinateRegion(center: currentCenter,
                                       span: MKCoordinateSpan(
                                           latitudeDelta:  InteractiveMapView.spanForRadius(clamped),
                                           longitudeDelta: InteractiveMapView.spanForRadius(clamped))),
                    animated: false
                )
            case .ended, .cancelled:
                parent.radiusMiles = clamped
                mapView.setRegion(
                    MKCoordinateRegion(center: currentCenter,
                                       span: MKCoordinateSpan(
                                           latitudeDelta:  InteractiveMapView.spanForRadius(clamped),
                                           longitudeDelta: InteractiveMapView.spanForRadius(clamped))),
                    animated: true
                )
                parent.onDragEnded()
            default: break
            }
        }

        /// Shifts the viewport when the finger is near a map edge, allowing unlimited dragging
        private func panToEdgeIfNeeded(touchPoint pt: CGPoint, in mapView: MKMapView) {
            let bounds = mapView.bounds
            let margin: CGFloat = 44
            var offsetX: CGFloat = 0
            var offsetY: CGFloat = 0
            if pt.x < margin                 { offsetX = pt.x - margin }
            if pt.x > bounds.width  - margin { offsetX = pt.x - (bounds.width  - margin) }
            if pt.y < margin                 { offsetY = pt.y - margin }
            if pt.y > bounds.height - margin { offsetY = pt.y - (bounds.height - margin) }
            guard offsetX != 0 || offsetY != 0 else { return }

            let damping: Double = 0.12
            let latScale = mapView.region.span.latitudeDelta  / Double(mapView.bounds.height) * damping
            let lngScale = mapView.region.span.longitudeDelta / Double(mapView.bounds.width)  * damping
            let newCenter = CLLocationCoordinate2D(
                latitude:  mapView.region.center.latitude  - Double(offsetY) * latScale,
                longitude: mapView.region.center.longitude + Double(offsetX) * lngScale
            )
            mapView.setRegion(
                MKCoordinateRegion(center: newCenter, span: mapView.region.span),
                animated: false
            )
            // Arc needs to redraw after viewport shifts
            arcHandleView?.setNeedsLayout()
        }

        /// Updates the circle + arc to a new center position. No overlay recreation needed.
        private func redrawCircle(in mapView: MKMapView, center: CLLocationCoordinate2D, radiusMeters: Double) {
            arcHandleView?.mapCenter = center
            arcHandleView?.radiusMeters = radiusMeters
            arcHandleView?.setNeedsLayout()
        }
    }
}

// MARK: - HomeMapWidget

struct HomeMapWidget: View {
    let locationLabel: String
    @Binding var isExpanded: Bool
    var onRadiusChanged: (Double, CLLocationCoordinate2D) -> Void = { _, _ in }
    var onLocationResolved: (String) -> Void = { _ in }
    var onRadiusModeChanged: (Bool) -> Void = { _ in }

    @State private var mapCenter = CLLocationCoordinate2D(latitude: 34.0224, longitude: -118.2851)
    @State private var radiusMiles = 2.0
    @State private var useRadius = false
    @State private var collapseTask: DispatchWorkItem? = nil
    /// Broad city/area label (e.g. "Los Angeles") — shown in city-wide mode.
    @State private var cityLabel = ""
    /// Specific neighborhood label (e.g. "University Park") — shown in radius mode.
    @State private var specificLabel = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            InteractiveMapView(
                radiusMiles: $radiusMiles,
                center: $mapCenter,
                isExpanded: isExpanded,
                showRadius: useRadius,
                onDragBegan: { collapseTask?.cancel() },
                onDragEnded: { scheduleAutoCollapse() },
                onMapTapped: { handleMapTap() },
                onCenterChanged: { newCenter in
                    mapCenter = newCenter
                    if useRadius { onRadiusChanged(radiusMiles, newCenter) }
                    reverseGeocode(newCenter)
                }
            )
            .allowsHitTesting(isExpanded)

            // Radius label — top center, shown only when expanded and radius mode is on
            if isExpanded && useRadius {
                VStack(spacing: 0) {
                    Text(String(format: "%.1f mi", radiusMiles))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.sage)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.92))
                        .clipShape(Capsule())
                        .padding(.top, 10)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // Bottom controls — toggle row + location bar
            VStack(spacing: 0) {
                // Toggle row — only visible when expanded
                if isExpanded {
                    HStack {
                        Text("SEARCH WITHIN A SPECIFIC RADIUS")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(1.0)
                            .foregroundColor(AppTheme.muted)
                        Spacer()
                        Toggle("", isOn: $useRadius)
                            .labelsHidden()
                            .tint(AppTheme.sage)
                            .onChange(of: useRadius) { _, newVal in
                                onRadiusModeChanged(newVal)
                                let label = newVal ? specificLabel : cityLabel
                                if !label.isEmpty { onLocationResolved(label) }
                                if newVal { onRadiusChanged(radiusMiles, mapCenter) }
                                // Reset the auto-collapse timer so the user has a full
                                // 3 seconds to start interacting after toggling.
                                scheduleAutoCollapse()
                            }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.surface.opacity(0.96))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Location bar — always visible
                HStack {
                    HStack(spacing: 7) {
                        Circle().fill(AppTheme.sage).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(useRadius ? specificLabel : cityLabel)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.onSurface)
                                .animation(.easeInOut(duration: 0.3), value: useRadius)
                            Text(useRadius
                                 ? String(format: "Within %.1f mi", radiusMiles)
                                 : "City-wide search")
                                .font(.system(size: 10, weight: .light))
                                .foregroundColor(AppTheme.muted)
                                .animation(.easeInOut(duration: 0.2), value: useRadius)
                        }
                    }
                    Spacer()
                    Button { expand() } label: {
                        Text("Change")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.sage)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppTheme.surface.opacity(0.96))
            }
        }
        .frame(height: isExpanded ? 290 : 180)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture { if !isExpanded { handleMapTap() } }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.35), value: isExpanded)
        .onChange(of: radiusMiles) { _, newVal in
            if useRadius { onRadiusChanged(newVal, mapCenter) }
        }
        .onAppear {
            reverseGeocode(mapCenter)
        }
    }

    private func reverseGeocode(_ coord: CLLocationCoordinate2D) {
        CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        ) { placemarks, error in
            let city: String
            let specific: String
            if let p = placemarks?.first, error == nil {
                city     = p.locality ?? p.administrativeArea ?? Self.coordString(coord)
                specific = p.subLocality ?? p.locality ?? p.administrativeArea ?? Self.coordString(coord)
            } else {
                city     = Self.coordString(coord)
                specific = Self.coordString(coord)
            }
            DispatchQueue.main.async {
                self.cityLabel    = city
                self.specificLabel = specific
                self.onLocationResolved(self.useRadius ? specific : city)
            }
        }
    }

    private static func coordString(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.4f° N, %.4f° W", c.latitude, abs(c.longitude))
    }

    private func handleMapTap() {
        guard !isExpanded else { collapse(); return }
        withAnimation(.easeInOut(duration: 0.35)) { isExpanded = true }
        scheduleAutoCollapse()
    }

    private func expand() {
        guard !isExpanded else { return }
        withAnimation(.easeInOut(duration: 0.35)) { isExpanded = true }
        scheduleAutoCollapse()
    }

    private func collapse() {
        collapseTask?.cancel()
        withAnimation(.easeInOut(duration: 0.35)) { isExpanded = false }
    }

    private func scheduleAutoCollapse() {
        collapseTask?.cancel()
        let task = DispatchWorkItem { collapse() }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: task)
    }
}
