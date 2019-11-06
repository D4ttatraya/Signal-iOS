//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSGroupThread.h"
#import "TSAttachmentStream.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSGroupThreadAvatarChangedNotification = @"TSGroupThreadAvatarChangedNotification";
NSString *const TSGroupThread_NotificationKey_UniqueId = @"TSGroupThread_NotificationKey_UniqueId";

@implementation TSGroupThread

#define TSGroupThreadPrefix @"g"

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
           conversationColorName:(ConversationColorName)conversationColorName
                    creationDate:(nullable NSDate *)creationDate
                      isArchived:(BOOL)isArchived
            lastInteractionRowId:(int64_t)lastInteractionRowId
                    messageDraft:(nullable NSString *)messageDraft
                  mutedUntilDate:(nullable NSDate *)mutedUntilDate
                           rowId:(int64_t)rowId
           shouldThreadBeVisible:(BOOL)shouldThreadBeVisible
                      groupModel:(TSGroupModel *)groupModel
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId
             conversationColorName:conversationColorName
                      creationDate:creationDate
                        isArchived:isArchived
              lastInteractionRowId:lastInteractionRowId
                      messageDraft:messageDraft
                    mutedUntilDate:mutedUntilDate
                             rowId:rowId
             shouldThreadBeVisible:shouldThreadBeVisible];

    if (!self) {
        return self;
    }

    _groupModel = groupModel;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (instancetype)initWithGroupModel:(TSGroupModel *)groupModel
{
    OWSAssertDebug(groupModel);
    OWSAssertDebug(groupModel.groupId.length > 0);
    for (SignalServiceAddress *address in groupModel.groupMembers) {
        OWSAssertDebug(address.isValid);
    }

    NSString *uniqueIdentifier = [[self class] threadIdFromGroupId:groupModel.groupId];
    self = [super initWithUniqueId:uniqueIdentifier];
    if (!self) {
        return self;
    }

    _groupModel = groupModel;

    return self;
}

- (instancetype)initWithGroupId:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);

    SignalServiceAddress *localAddress = TSAccountManager.localAddress;
    OWSAssertDebug(localAddress.isValid);

    // GroupsV2 TODO: Move to group manager.
    TSGroupModel *groupModel = [[TSGroupModel alloc] initWithGroupId:groupId
                                                                name:nil
                                                          avatarData:nil
                                                             members:@[ localAddress ]
                                                       groupsVersion:GroupManager.defaultGroupsVersion];

    self = [self initWithGroupModel:groupModel];
    if (!self) {
        return self;
    }

    return self;
}

+ (nullable instancetype)threadWithGroupId:(NSData *)groupId transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);

    NSString *uniqueId = [self threadIdFromGroupId:groupId];
    return [TSGroupThread anyFetchGroupThreadWithUniqueId:uniqueId transaction:transaction];
}

+ (nullable instancetype)getThreadWithGroupId:(NSData *)groupId transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);
    OWSAssertDebug(transaction);

    NSString *uniqueId = [self threadIdFromGroupId:groupId];
    return [TSGroupThread anyFetchGroupThreadWithUniqueId:uniqueId transaction:transaction];
}

+ (instancetype)getOrCreateThreadWithGroupId:(NSData *)groupId transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(groupId.length > 0);
    OWSAssertDebug(transaction);

    TSGroupThread *thread = [self getThreadWithGroupId:groupId transaction:transaction];
    if (!thread) {
        thread = [[self alloc] initWithGroupId:groupId];
        [thread anyInsertWithTransaction:transaction];
    }
    return thread;
}

+ (instancetype)getOrCreateThreadWithGroupId:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);

    __block TSGroupThread *thread;
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        thread = [self getOrCreateThreadWithGroupId:groupId transaction:transaction];
    }];
    return thread;
}

+ (instancetype)getOrCreateThreadWithGroupModel:(TSGroupModel *)groupModel
                                    transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(groupModel);
    OWSAssertDebug(groupModel.groupId.length > 0);
    OWSAssertDebug(transaction);

    TSGroupThread *thread = (TSGroupThread *)[self anyFetchWithUniqueId:[self threadIdFromGroupId:groupModel.groupId]
                                                            transaction:transaction];

    if (!thread) {
        thread = [[TSGroupThread alloc] initWithGroupModel:groupModel];
        [thread anyInsertWithTransaction:transaction];
    }
    return thread;
}

+ (instancetype)getOrCreateThreadWithGroupModel:(TSGroupModel *)groupModel
{
    OWSAssertDebug(groupModel);
    OWSAssertDebug(groupModel.groupId.length > 0);

    __block TSGroupThread *thread;
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        thread = [self getOrCreateThreadWithGroupModel:groupModel transaction:transaction];
    }];
    return thread;
}

+ (NSString *)threadIdFromGroupId:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);

    return [TSGroupThreadPrefix stringByAppendingString:[groupId base64EncodedString]];
}

+ (NSData *)groupIdFromThreadId:(NSString *)threadId
{
    OWSAssertDebug(threadId.length > 0);

    return [NSData dataFromBase64String:[threadId substringWithRange:NSMakeRange(1, threadId.length - 1)]];
}

- (NSArray<SignalServiceAddress *> *)recipientAddresses
{
    NSMutableArray<SignalServiceAddress *> *groupMembers = [self.groupModel.groupMembers mutableCopy];
    if (groupMembers == nil) {
        return @[];
    }

    [groupMembers removeObject:TSAccountManager.localAddress];

    return [groupMembers copy];
}

// @returns all threads to which the recipient is a member.
//
// @note If this becomes a hotspot we can extract into a YapDB View.
// As is, the number of groups should be small (dozens, *maybe* hundreds), and we only enumerate them upon SN changes.
+ (NSArray<TSGroupThread *> *)groupThreadsWithAddress:(SignalServiceAddress *)address
                                          transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    NSMutableArray<TSGroupThread *> *groupThreads = [NSMutableArray new];

    [TSThread anyEnumerateWithTransaction:transaction
                                  batched:YES
                                    block:^(TSThread *thread, BOOL *stop) {
                                        if ([thread isKindOfClass:[TSGroupThread class]]) {
                                            TSGroupThread *groupThread = (TSGroupThread *)thread;
                                            if ([groupThread.groupModel.groupMembers containsObject:address]) {
                                                [groupThreads addObject:groupThread];
                                            }
                                        }
                                    }];

    return [groupThreads copy];
}

- (BOOL)isGroupThread
{
    return true;
}

- (BOOL)isLocalUserInGroup
{
    SignalServiceAddress *_Nullable localAddress = TSAccountManager.localAddress;
    if (localAddress == nil) {
        return NO;
    }

    return [self.groupModel.groupMembers containsObject:localAddress];
}

- (NSString *)groupNameOrDefault
{
    return self.groupModel.groupNameOrDefault;
}

+ (NSString *)defaultGroupName
{
    return NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
}

- (void)leaveGroupWithSneakyTransaction
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self leaveGroupWithTransaction:transaction];
    }];
}

- (void)leaveGroupWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    SignalServiceAddress *_Nullable localAddress = [TSAccountManager localAddressWithTransaction:transaction];
    OWSAssertDebug(localAddress);

    [self anyUpdateGroupThreadWithTransaction:transaction
                                        block:^(TSGroupThread *thread) {
                                            NSMutableArray<SignalServiceAddress *> *newGroupMembers =
                                                [thread.groupModel.groupMembers mutableCopy];
                                            [newGroupMembers removeObject:localAddress];
                                            thread.groupModel.groupMembers = newGroupMembers;
                                        }];
}

#pragma mark - Avatar

- (void)updateAvatarWithAttachmentStream:(TSAttachmentStream *)attachmentStream
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self updateAvatarWithAttachmentStream:attachmentStream transaction:transaction];
    }];
}

- (void)updateAvatarWithAttachmentStream:(TSAttachmentStream *)attachmentStream
                             transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(attachmentStream);
    OWSAssertDebug(transaction);

    [self anyUpdateGroupThreadWithTransaction:transaction
                                        block:^(TSGroupThread *thread) {
                                            NSData *_Nullable attachmentData =
                                                [NSData dataWithContentsOfFile:attachmentStream.originalFilePath];
                                            if (attachmentData.length < 1) {
                                                return;
                                            }
                                            if (thread.groupModel.groupAvatarData.length > 0 &&
                                                [thread.groupModel.groupAvatarData isEqualToData:attachmentData]) {
                                                // Avatar did not change.
                                                return;
                                            }
                                            UIImage *_Nullable avatarImage = [attachmentStream thumbnailImageSmallSync];
                                            [thread.groupModel setGroupAvatarDataWithImage:avatarImage];
                                        }];

    [transaction addCompletionWithBlock:^{
        [self fireAvatarChangedNotification];
    }];

    // Avatars are stored directly in the database, so there's no need
    // to keep the attachment around after assigning the image.
    [attachmentStream anyRemoveWithTransaction:transaction];
}

- (void)fireAvatarChangedNotification
{
    OWSAssertIsOnMainThread();

    NSDictionary *userInfo = @{ TSGroupThread_NotificationKey_UniqueId : self.uniqueId };

    [[NSNotificationCenter defaultCenter] postNotificationName:TSGroupThreadAvatarChangedNotification
                                                        object:self.uniqueId
                                                      userInfo:userInfo];
}

+ (ConversationColorName)defaultConversationColorNameForGroupId:(NSData *)groupId
{
    OWSAssertDebug(groupId.length > 0);

    return [self.class stableColorNameForNewConversationWithString:[self threadIdFromGroupId:groupId]];
}

@end

NS_ASSUME_NONNULL_END
