import React, { useCallback, useMemo, useState } from "react";
import { EventRegistrationForm, Redirect, SharedLayout, useEventRegistrations } from "@app/components";
import {
  useDeleteEventRegistrationMutation,
  useEventRegistrationPageQuery,
} from "@app/graphql";
import { List, PageHeader, Typography } from "antd";
import { NextPage } from "next";
import { useRouter } from "next/router";
import useTranslation from "next-translate/useTranslation";

const EventRegistrationPage: NextPage = () => {
  const { t, lang } = useTranslation("register");
  const router = useRouter();
  const { eventId, quotaId } = router.query;

  const query = useEventRegistrationPageQuery({
    variables: { eventId, quotaId },
  });
  const { loading, error } = query;

  const currentUser = query?.data?.currentUser;
  const event = query?.data?.event;
  const quota = query?.data?.quota;
  const { signupClosed, signupUpcoming } = event || {};

  const { name, primaryEmail } = currentUser || {};
  // TODO: The users table schema could be changed to include first
  // and last names. For now infer first and last name like this...
  const [firstName, lastName] = name ? name?.split(" ") : [];

  const formInitialValues = {
    firstName,
    lastName,
    email: primaryEmail,
  };

  // Subscribe to registrations created after this timestamp
  const after = useMemo(() => new Date().toISOString(), []);
  const recentRegistrations = useEventRegistrations(eventId as string, after)
  const [deleteRegistration] = useDeleteEventRegistrationMutation();
  const [updateToken, setUpdateToken] = useState<string | undefined>(undefined)

  const handleGoBack = useCallback(async () => {
    // Delete the pending registration if the user goes back to event page
    if (updateToken) {
      await deleteRegistration({
        variables: { updateToken },
      });
    }
    router.push(`/event/${event.slug}`)
  }, [deleteRegistration, router, event, updateToken]);

  // If event or quota is not found, or if event
  // registration is not open redirect to index
  if (
    !loading &&
    !error &&
    (!event || !quota || signupClosed || signupUpcoming)
  ) {
    return <Redirect href="/" layout />;
  }

  return (
    <SharedLayout query={query} title="">
      <PageHeader
        title={`${t("title")} ${event?.name[lang] || t("common:loading")} - ${quota?.title[lang] || t("common:loading")
          }`}
        onBack={handleGoBack}
      />
      <EventRegistrationForm
        eventId={event?.id}
        formRedirect={{
          pathname: "/event/[slug]",
          query: { slug: event?.slug },
        }}
        initialValues={formInitialValues}
        quotaId={quota?.id}
        // Used to delete an unfinished registration
        setUpdateToken={setUpdateToken}
        type="create"
      />
      {recentRegistrations && (
        <List
          data-cy="eventregistrationpage-recent-registrations-list"
          dataSource={recentRegistrations}
          header={<div>{t("recentlyRegisteredHeader")}</div>}
          renderItem={(item, i) => {
            const name = item?.fullName;
            const quota = item?.quota?.title[lang];
            return i === 0 || name ? (
              <List.Item>
                <Typography.Text>
                  {i === 0
                    ? t("you")
                    : `${name} ${t("recentlyRegisteredListItem")} ${quota}`}
                </Typography.Text>
              </List.Item>
            ) : null;
          }}
          bordered
        />
      )}
    </SharedLayout>
  );
};

export default EventRegistrationPage;
