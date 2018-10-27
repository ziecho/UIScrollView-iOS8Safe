//
//  UIScrollView+iOS8Safe.m
//  EasiPass
//
//  Created by zie on 26/10/2018.
//  Copyright © 2018 ziecho. All rights reserved.
//

#import "UIScrollView+iOS8Safe.h"
#import <objc/message.h>

#define object_getIvarValue(object, name) object_getIvar(object, class_getInstanceVariable([object class], name))

#define object_setIvarValue(object, name, value) object_setIvar(object, class_getInstanceVariable([object class], name), value)

#define IOS_VERSION ([[[UIDevice currentDevice] systemVersion] floatValue])

CG_INLINE void
SwizzleMethod(Class _class, SEL _originSelector, SEL _newSelector) {
    Method oriMethod = class_getInstanceMethod(_class, _originSelector);
    Method newMethod = class_getInstanceMethod(_class, _newSelector);
    BOOL isAddedMethod = class_addMethod(_class, _originSelector, method_getImplementation(newMethod), method_getTypeEncoding(newMethod));
    if (isAddedMethod) {
        class_replaceMethod(_class, _newSelector, method_getImplementation(oriMethod), method_getTypeEncoding(oriMethod));
    } else {
        method_exchangeImplementations(oriMethod, newMethod);
    }
}


@interface ReleaseDelegateCleaner : NSObject
@property (nonatomic, strong) NSPointerArray *scrollViews;
@end

@implementation ReleaseDelegateCleaner

- (void)dealloc {
    [self cleanScrollViewsDelegate];
}

- (void)recordDelegatedScrollView:(UIScrollView *)scrollView {
    NSUInteger index = [self.scrollViews.allObjects indexOfObject:scrollView];
    if (index == NSNotFound) {
        [self.scrollViews addPointer:(__bridge void *)(scrollView)];
    }
}

- (void)removeDelegatedScrollView:(UIScrollView *)scrollView {
    NSUInteger index = [self.scrollViews.allObjects indexOfObject:scrollView];
    if (index != NSNotFound) {
        [self.scrollViews removePointerAtIndex:index];
    }
}

- (void)cleanScrollViewsDelegate {
    [self.scrollViews.allObjects enumerateObjectsUsingBlock:^(UIScrollView *scrollView, NSUInteger idx, BOOL * _Nonnull stop) {
        object_setIvarValue(scrollView, "_delegate", nil);
        if ([scrollView isKindOfClass:[UITableView class]] || [scrollView isKindOfClass:[UICollectionView class]]) {
            object_setIvarValue(scrollView, "_dataSource", nil);
        }
    }];
}

- (void)setScrollViews:(NSPointerArray *)scrollViews {
    objc_setAssociatedObject(self, @selector(scrollViews), scrollViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSPointerArray *)scrollViews {
    NSPointerArray *scrollViews = objc_getAssociatedObject(self, _cmd);
    if (!scrollViews) {
        scrollViews = [NSPointerArray weakObjectsPointerArray];
        [self setScrollViews:scrollViews];
    }
    return scrollViews;
}

@end

@interface NSObject (iOS8Safe)
@property (nonatomic, readonly) ReleaseDelegateCleaner *iOS8DelegateCleaner;
@end

@implementation NSObject (EPiOS8ScrollViewSafe)

- (ReleaseDelegateCleaner *)iOS8DelegateCleaner {
    ReleaseDelegateCleaner *cleaner = objc_getAssociatedObject(self, _cmd);
    if (!cleaner) {
        cleaner = [ReleaseDelegateCleaner new];
        objc_setAssociatedObject(self, _cmd, cleaner, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return cleaner;
}

@end


@implementation UITableView (iOS8Safe)

- (void)safe_setDataSource:(id<UITableViewDataSource>)dataSource {
    if (dataSource) {
        [[(NSObject *)dataSource iOS8DelegateCleaner] recordDelegatedScrollView:self];
        
    } else {
        id _dataSource = object_getIvarValue(self, "_dataSource");
        [[(NSObject *)_dataSource iOS8DelegateCleaner] removeDelegatedScrollView:self];
    }
    
    [self safe_setDataSource:dataSource];
}

@end


@implementation UICollectionView (iOS8Safe)

- (void)safe_setDataSource:(id<UICollectionViewDataSource>)dataSource {
    if (dataSource) {
        [[(NSObject *)dataSource iOS8DelegateCleaner] recordDelegatedScrollView:self];
        
    } else {
        id _dataSource = object_getIvarValue(self, "_dataSource");
        [[(NSObject *)_dataSource iOS8DelegateCleaner] removeDelegatedScrollView:self];
    }
    
    [self safe_setDataSource:dataSource];
}

@end


@implementation UIScrollView (iOS8Safe)

- (void)safe_will_dealloc {
    objc_setAssociatedObject(self,  @selector(safe_will_dealloc), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    [self safe_will_dealloc];
}

+ (void)load {
    if (IOS_VERSION < 9.0) {
        SwizzleMethod([UIScrollView class], sel_registerName("dealloc"), @selector(safe_will_dealloc));
        SwizzleMethod([UIScrollView class], @selector(setDelegate:), @selector(safe_setDelegate:));
        
        SwizzleMethod([UITableView class], @selector(setDataSource:), @selector(safe_setDataSource:));
        SwizzleMethod([UICollectionView class], @selector(setDataSource:), @selector(safe_setDataSource:));
    }
}

- (void)safe_setDelegate:(id<UIScrollViewDelegate>)delegate {
    BOOL willDealloc = [objc_getAssociatedObject(self, @selector(safe_will_dealloc)) boolValue];
    
    if (!willDealloc) {
        id _delegate = object_getIvarValue(self, "_delegate");
        
        if (_delegate != delegate) {
            [[(NSObject *)_delegate iOS8DelegateCleaner] removeDelegatedScrollView:self];
            [[(NSObject *)delegate iOS8DelegateCleaner] recordDelegatedScrollView:self];
        }
        
    }
    
    [self safe_setDelegate:delegate];
}

@end

