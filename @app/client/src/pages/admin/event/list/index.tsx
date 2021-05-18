import React from "react"
import {
  AdminLayout,
  AdminTableActions,
  ServerPaginatedTable,
} from "@app/components"
import {
  Event,
  ListEventsDocument,
  useDeleteEventMutation,
  useListEventsPageQuery,
} from "@app/graphql"
import {
  Badge,
  Col,
  PageHeader,
  Popover,
  Progress,
  Row,
  Tag,
  Typography,
} from "antd"
import useBreakpoint from "antd/lib/grid/hooks/useBreakpoint"
import dayjs from "dayjs"
import { reduce } from "lodash"
import { NextPage } from "next"
import Link from "next/link"
import useTranslation from "next-translate/useTranslation"

const Admin_ListEvents: NextPage = () => {
  const { t, lang } = useTranslation("admin")
  const query = useListEventsPageQuery()
  const screens = useBreakpoint()
  const isMobile = screens["xs"]

  const eventCategories = query?.data?.eventCategories?.nodes

  const actionsColumn = {
    title: "",
    key: "actions",
    render: (_name: string, event: Event) => {
      return (
        <AdminTableActions
          adminUrl="event"
          dataType={event}
          deleteConfirmTranslate={t("events.delete.confirmText")}
          deleteMutation={useDeleteEventMutation}
        />
      )
    },
  }
  const nameColumn = {
    title: t("common:name"),
    dataIndex: ["name", lang],
    key: "name",
    render: (name: string, event: Event) => (
      <Link
        as={`/event/${event.slug}`}
        href={{
          pathname: "/event/[slug]",
          query: {
            slug: event.slug,
          },
        }}
      >
        <a>{name}</a>
      </Link>
    ),
  }
  const isDraftColumn = {
    title: t("events:forms.isDraft"),
    dataIndex: ["isDraft"],
    key: "isDraft",
    render: (isDraft: string) => (
      <Badge
        color={isDraft ? "yellow" : "green"}
        text={
          isDraft ? t("events:forms.isDraft") : t("events:forms.isNotDraft")
        }
      />
    ),
  }

  const columns = !isMobile
    ? [
        actionsColumn,
        isDraftColumn,
        nameColumn,
        {
          title: t("events:category"),
          dataIndex: ["category", "name", lang],
          key: "categoryName",
          filters: [
            ...Array.from(
              new Set(eventCategories?.map((o) => o.name[lang]))
            ).map((name) => ({ text: name, value: name })),
          ],
          onFilter: (value: string | number | boolean, record: Event) =>
            record?.category?.name[lang].indexOf(value) === 0,
          sorter: (a: Event, b: Event) =>
            a?.name[lang]?.localeCompare(b?.name[lang] || ""),
          render: (name: string, record: Event, index: number) => {
            console.log(record)
            return (
              <Tag key={`${record.id}-${index}`} color={record.category.color}>
                {name?.toUpperCase()}
              </Tag>
            )
          },
        },
        {
          title: t("events.list.registrations"),
          key: "registrations",
          render: (event: Event) => {
            const popoverContent = (
              <>
                {event.quotas.nodes.map((quota) => {
                  const quotaRegistrations = quota.registrations.totalCount
                  return (
                    <Row key={quota.id} style={{ minWidth: "20rem" }}>
                      <Col span={5}>{quota.title[lang]}</Col>
                      <Col span={12} style={{ marginRight: "10px" }}>
                        <Progress
                          percent={(quotaRegistrations * 100) / quota.size}
                          showInfo={false}
                        />
                      </Col>
                      <Col flex="auto" style={{ whiteSpace: "nowrap" }}>
                        {quotaRegistrations} / {quota.size}
                      </Col>
                    </Row>
                  )
                })}
              </>
            )

            const numRegistrations = event.registrations.totalCount
            const totalSize = reduce(
              event.quotas.nodes,
              (acc: number, quota) => acc + quota.size,
              0
            )
            return (
              <Popover
                content={popoverContent}
                title={t("events.list.registrationsPerQuota")}
              >
                <Row gutter={12}>
                  <Col span={8}>
                    <Typography.Text style={{ whiteSpace: "nowrap" }}>
                      {numRegistrations} / {totalSize}
                    </Typography.Text>
                  </Col>
                  <Col span={12}>
                    <Progress
                      percent={(numRegistrations * 100) / totalSize}
                      showInfo={false}
                      style={{ marginLeft: "12px" }}
                    />
                  </Col>
                </Row>
              </Popover>
            )
          },
        },
        {
          title: t("events:startTime"),
          dataIndex: "eventStartTime",
          render: (startTime: string) => dayjs(startTime).format("l LTS"),
        },
      ]
    : [actionsColumn, nameColumn]

  return (
    <AdminLayout href="/admin/event/list" query={query}>
      <Row>
        <Col flex={1}>
          <PageHeader title={t("pageTitle.listEvent")} />
          <ServerPaginatedTable
            columns={columns}
            data-cy="adminpage-events"
            dataField="events"
            queryDocument={ListEventsDocument}
            showPagination={true}
            size="middle"
          />
        </Col>
      </Row>
    </AdminLayout>
  )
}

export default Admin_ListEvents
