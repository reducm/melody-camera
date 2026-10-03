import SwiftUI
import MelodyCore
#if os(iOS)
import UIKit

/// UIPageViewController 提供系统横向翻页，每页独立使用原生滚动缩放。
struct PhotoViewer: View {
    @ObservedObject var studio: StudioModel
    let photoIDs: [UUID]
    @State var currentID: UUID
    let useOriginal: Bool
    @State var showTemplate: Bool
    @State private var dragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    private var currentPhoto: ProjectPhoto? { studio.currentProject?.photos.first { $0.id == currentID } }
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(max(0.25,1 - dragOffset/500)).ignoresSafeArea()
            PhotoPager(ids:photoIDs,selected:$currentID,showTemplate:showTemplate,
                       load:{ try await studio.galleryPhoto($0,original:useOriginal) },
                       dragged:{ dragOffset = $0 },
                       finishedDrag:{ distance, velocity in
                           if distance > 120 || (distance > 30 && velocity > 900) { dismiss() }
                           else { withAnimation(.spring(response:0.3)) { dragOffset = 0 } }
                       })
                .offset(y:dragOffset).scaleEffect(1 - min(dragOffset/3000,0.12)).ignoresSafeArea()
            HStack {
                Button("完成") { dismiss() }.padding(12).background(.black.opacity(0.7), in: Capsule())
                Spacer()
                HStack(spacing:16) {
                    Button { move(-1) } label: { Image(systemName:"chevron.left") }.disabled(currentID == photoIDs.first).accessibilityLabel("上一张照片")
                    Text("\((photoIDs.firstIndex(of:currentID) ?? 0)+1) / \(photoIDs.count)").font(.subheadline.monospacedDigit())
                    Button { move(1) } label: { Image(systemName:"chevron.right") }.disabled(currentID == photoIDs.last).accessibilityLabel("下一张照片")
                }
                Spacer()
                if currentPhoto?.capturedFollowing != nil {
                    Button { showTemplate.toggle() } label: {
                        Label(showTemplate ? "隐藏模板" : "显示模板", systemImage: "square.on.square")
                    }.padding(12).background(.black.opacity(0.7), in: Capsule())
                }
            }.padding().opacity(dragOffset == 0 ? 1 : 0)
        }.foregroundStyle(.white)
            .presentationBackground(.clear)
            .onDisappear { let id = currentID; Task { await studio.selectProjectPhoto(id) } }
    }
    private func move(_ delta:Int) {
        guard let index = photoIDs.firstIndex(of:currentID), photoIDs.indices.contains(index+delta) else { return }
        currentID = photoIDs[index+delta]
    }
}
private struct PhotoPager: UIViewControllerRepresentable {
    let ids: [UUID]
    @Binding var selected: UUID
    let showTemplate: Bool
    let load: @MainActor (UUID) async throws -> GalleryPhoto
    let dragged: (CGFloat) -> Void
    let finishedDrag: (CGFloat, CGFloat) -> Void
    func makeUIViewController(context: Context) -> GalleryController {
        let controller = GalleryController(ids:ids,initial:selected,load:load)
        controller.changed = { selected = $0 }
        controller.dragged = dragged; controller.finishedDrag = finishedDrag
        controller.showTemplate = showTemplate
        return controller
    }
    func updateUIViewController(_ controller: GalleryController, context: Context) {
        controller.showTemplate = showTemplate
        controller.changed = { selected = $0 }
        controller.select(selected)
    }
}
private final class GalleryController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    let ids: [UUID]
    let loadPhoto: @MainActor (UUID) async throws -> GalleryPhoto
    var changed: (UUID) -> Void = { _ in }
    var dragged: (CGFloat) -> Void = { _ in }
    var finishedDrag: (CGFloat,CGFloat) -> Void = { _,_ in }
    private var transitioning = false
    private var requestedID: UUID?
    var showTemplate = false { didSet { for page in viewControllers ?? [] { (page as? PhotoPageController)?.showTemplate = showTemplate } } }
    init(ids:[UUID],initial:UUID,load:@escaping @MainActor (UUID) async throws -> GalleryPhoto) {
        self.ids = ids; self.loadPhoto = load
        super.init(transitionStyle:.scroll,navigationOrientation:.horizontal,options:nil)
        dataSource = self; delegate = self
        setViewControllers([page(initial)],direction:.forward,animated:false)
    }
    required init?(coder:NSCoder) { fatalError("不使用 storyboard") }
    private var pagerScroll: UIScrollView? { view.subviews.compactMap { $0 as? UIScrollView }.first }
    private func page(_ id:UUID) -> PhotoPageController {
        let page = PhotoPageController(id:id,load:loadPhoto)
        page.showTemplate = showTemplate
        page.zoomed = { [weak self] zoomed in self?.pagerScroll?.isScrollEnabled = !zoomed }
        page.dragged = { [weak self] value in self?.dragged(value) }
        page.finishedDrag = { [weak self] distance,velocity in self?.finishedDrag(distance,velocity) }
        return page
    }
    func select(_ id:UUID) {
        requestedID = id
        guard !transitioning, let current = viewControllers?.first as? PhotoPageController,
              current.id != id, let oldIndex = ids.firstIndex(of:current.id), let newIndex = ids.firstIndex(of:id) else { return }
        transitioning = true
        setViewControllers([page(id)],direction:newIndex > oldIndex ? .forward : .reverse,animated:true) { [weak self] _ in
            guard let self else { return }
            transitioning = false; pagerScroll?.isScrollEnabled = true
            if let requestedID { select(requestedID) }
        }
    }
    func pageViewController(_ pageViewController:UIPageViewController,willTransitionTo pendingViewControllers:[UIViewController]) {
        transitioning = true
    }
    func pageViewController(_ pageViewController:UIPageViewController,viewControllerBefore controller:UIViewController) -> UIViewController? {
        guard let page = controller as? PhotoPageController, let index = ids.firstIndex(of:page.id), index > 0 else { return nil }
        return self.page(ids[index-1])
    }
    func pageViewController(_ pageViewController:UIPageViewController,viewControllerAfter controller:UIViewController) -> UIViewController? {
        guard let page = controller as? PhotoPageController, let index = ids.firstIndex(of:page.id), index+1 < ids.count else { return nil }
        return self.page(ids[index+1])
    }
    func pageViewController(_ pageViewController:UIPageViewController,didFinishAnimating finished:Bool,previousViewControllers:[UIViewController],transitionCompleted completed:Bool) {
        transitioning = false
        guard let page = viewControllers?.first as? PhotoPageController else { return }
        requestedID = page.id
        page.showTemplate = showTemplate
        pagerScroll?.isScrollEnabled = page.photoView.zoomScale <= 1.01
        changed(page.id)
    }
}
private final class PhotoPageController: UIViewController {
    let id: UUID
    let photoView = PhotoScrollView()
    let loadPhoto: @MainActor (UUID) async throws -> GalleryPhoto
    private var loading: Task<Void,Never>?
    private var content: GalleryPhoto?
    private let message = UILabel()
    var showTemplate = false { didSet { updateGuide() } }
    var zoomed: (Bool) -> Void = { _ in }
    var dragged: (CGFloat) -> Void = { _ in }
    var finishedDrag: (CGFloat,CGFloat) -> Void = { _,_ in }
    init(id:UUID,load:@escaping @MainActor (UUID) async throws -> GalleryPhoto) {
        self.id = id; self.loadPhoto = load; super.init(nibName:nil,bundle:nil)
    }
    required init?(coder:NSCoder) { fatalError("不使用 storyboard") }
    override func loadView() {
        view = photoView
        message.text = "正在读取照片…"; message.textColor = .white; message.textAlignment = .center; message.numberOfLines = 0
        message.translatesAutoresizingMaskIntoConstraints = false
        photoView.addSubview(message)
        NSLayoutConstraint.activate([message.centerXAnchor.constraint(equalTo:photoView.frameLayoutGuide.centerXAnchor),message.centerYAnchor.constraint(equalTo:photoView.frameLayoutGuide.centerYAnchor),message.widthAnchor.constraint(lessThanOrEqualTo:photoView.frameLayoutGuide.widthAnchor,multiplier:0.85)])
        photoView.zoomed = { [weak self] value in
            guard let self, self.view.window != nil else { return }
            self.zoomed(value)
        }
        photoView.dragged = { [weak self] in self?.dragged($0) }
        photoView.finishedDrag = { [weak self] in self?.finishedDrag($0,$1) }
    }
    override func viewWillAppear(_ animated:Bool) {
        super.viewWillAppear(animated)
        if let pager = parent as? UIPageViewController {
            for scroll in pager.view.subviews.compactMap({ $0 as? UIScrollView }) { photoView.coordinatePaging(scroll) }
        }
        guard content == nil, loading == nil else { return }
        loading = Task { [weak self] in
            guard let self else { return }
            defer { loading = nil }
            do {
                let result = try await loadPhoto(id)
                try Task.checkCancellation()
                guard let image = UIImage(data:result.data) else { throw ProjectFailure.missingOriginal }
                content = result; photoView.imageView.image = image
                message.isHidden = true; updateGuide(); photoView.setNeedsLayout()
            } catch is CancellationError {} catch { message.text = "照片暂时无法读取，可左右切换其他照片或返回。" }
        }
    }
    override func viewDidDisappear(_ animated:Bool) {
        super.viewDidDisappear(animated)
        loading?.cancel()
        // 原生分页只保留邻页；离开页面重置缩放，避免返回后无法翻页。
        photoView.setZoomScale(1,animated:false)
    }
    private func updateGuide() {
        photoView.plan = showTemplate ? content?.plan : nil
        photoView.outline = content?.outline; photoView.setNeedsLayout()
    }
}
final class PhotoScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let imageView = UIImageView()
    let guide = CAShapeLayer()
    var plan: ShotPlan?
    var outline: SubjectOutline?
    var zoomed: (Bool) -> Void = { _ in }
    var dragged: (CGFloat) -> Void = { _ in }
    var finishedDrag: (CGFloat,CGFloat) -> Void = { _,_ in }
    private var previousSize = CGSize.zero
    private lazy var dismissPan = UIPanGestureRecognizer(target:self,action:#selector(pullDown(_:)))
    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self; minimumZoomScale = 1; maximumZoomScale = 6
        panGestureRecognizer.isEnabled = false
        dismissPan.delegate = self; addGestureRecognizer(dismissPan)
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView); imageView.layer.addSublayer(guide)
        guide.strokeColor = UIColor.systemYellow.cgColor
        guide.fillColor = UIColor.systemYellow.withAlphaComponent(0.1).cgColor
        let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        tap.numberOfTapsRequired = 2; addGestureRecognizer(tap)
        accessibilityLabel = "全屏照片，可双指缩放或双击放大"
    }
    required init?(coder: NSCoder) { fatalError("不使用 storyboard") }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerPhoto(); let enlarged = zoomScale > 1.01
        panGestureRecognizer.isEnabled = enlarged; zoomed(enlarged)
    }
    func coordinatePaging(_ pager: UIScrollView) { pager.panGestureRecognizer.require(toFail:dismissPan) }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPan else { return true }
        let velocity = dismissPan.velocity(in:self)
        return zoomScale <= 1.01 && velocity.y > abs(velocity.x)
    }
    @objc private func pullDown(_ gesture: UIPanGestureRecognizer) {
        let distance = max(0,gesture.translation(in:window).y)
        switch gesture.state {
        case .changed: dragged(distance)
        case .ended: finishedDrag(distance,gesture.velocity(in:window).y)
        case .cancelled, .failed: finishedDrag(0,0)
        default: break
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return }
        if previousSize != bounds.size {
            previousSize = bounds.size
            setZoomScale(1, animated: false)
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            imageView.frame = CGRect(origin: .zero, size: CGSize(width: image.size.width * scale, height: image.size.height * scale))
            contentSize = imageView.bounds.size
        }
        centerPhoto()
        let size = imageView.bounds.size
        let path = UIBezierPath()
        if let plan {
            let box = plan.subject
            path.append(UIBezierPath(rect: CGRect(x:box.x * size.width,y:box.y * size.height,width:box.width * size.width,height:box.height * size.height)))
            if let placed = try? outline?.placed(in: box, canvasAspect: size.width / size.height) {
                for points in placed.paths {
                    guard let first = points.first else { continue }
                    path.move(to: CGPoint(x:first.x * size.width,y:first.y * size.height))
                    for point in points.dropFirst() { path.addLine(to: CGPoint(x:point.x * size.width,y:point.y * size.height)) }
                    path.close()
                }
            }
        }
        guide.frame = imageView.bounds; guide.path = path.cgPath; guide.lineWidth = 2 / zoomScale
    }
    private func centerPhoto() {
        imageView.center = CGPoint(x: max(bounds.width,contentSize.width)/2, y:max(bounds.height,contentSize.height)/2)
    }
    @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1 { setZoomScale(1, animated: true); return }
        let point = gesture.location(in: imageView)
        let size = CGSize(width:bounds.width/3,height:bounds.height/3)
        zoom(to: CGRect(x:point.x-size.width/2,y:point.y-size.height/2,width:size.width,height:size.height), animated: true)
    }
}
#endif
